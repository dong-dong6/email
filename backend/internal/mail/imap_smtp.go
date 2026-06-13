package mail

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"mime/quotedprintable"
	"net"
	netmail "net/mail"
	"net/smtp"
	"net/textproto"
	"regexp"
	"strconv"
	"strings"
	"time"

	"email/backend/internal/events"
	"email/backend/internal/model"
	"email/backend/internal/store"
)

const maxIMAPMessageBytes = 12 << 20

var literalPattern = regexp.MustCompile(`\{([0-9]+)\}\r?\n$`)

type IMAPSMTPConnector struct {
	provider model.Provider
	db       *store.Memory
	broker   *events.Broker
}

func (c IMAPSMTPConnector) Provider() model.Provider {
	return c.provider
}

func (c IMAPSMTPConnector) AuthorizeURL(state string) (string, error) {
	return "", errors.New("this connector uses IMAP/SMTP account credentials")
}

func (c IMAPSMTPConnector) Sync(ctx context.Context, account model.Account) error {
	account, err := NormalizeAccount(account)
	if err != nil {
		return err
	}
	client, err := dialIMAP(ctx, account)
	if err != nil {
		return err
	}
	defer client.close()
	if err := client.login(account.Username, account.Password); err != nil {
		return err
	}

	syncFolders := []struct {
		mailbox string
		role    string
	}{
		{"INBOX", "inbox"},
		{"SENT", "sent"},
		{"[Gmail]/Sent Mail", "sent"},
		{"Drafts", "drafts"},
		{"[Gmail]/Drafts", "drafts"},
	}

	for _, sf := range syncFolders {
		if err := c.syncFolder(ctx, client, account, sf.mailbox, sf.role); err != nil {
			continue
		}
	}

	_ = client.logout()
	return nil
}

func (c IMAPSMTPConnector) syncFolder(ctx context.Context, client *imapClient, account model.Account, mailbox, role string) error {
	if err := client.selectMailbox(mailbox); err != nil {
		return err
	}
	folder, err := folderByRole(c.db, account.ID, role)
	if err != nil {
		return err
	}

	since := time.Time{}
	if account.SyncCursor != "" {
		if t, err := time.Parse(time.RFC3339Nano, account.SyncCursor); err == nil {
			since = t
		}
	}

	var uids []string
	if since.IsZero() {
		uids, err = client.searchAll()
		if err != nil {
			return err
		}
		if len(uids) > 100 {
			uids = uids[len(uids)-100:]
		}
	} else {
		uids, err = client.searchSince(since)
		if err != nil {
			return err
		}
	}

	for _, uid := range uids {
		providerID := "imap:" + uid
		if existing, ok := c.db.FindMessageByProvider(account.ID, providerID); ok {
			if since.IsZero() || (existing.ReceivedAt != nil && existing.ReceivedAt.Before(since)) {
				continue
			}
		}

		raw, flags, err := client.fetchRFC822(uid)
		if err != nil {
			continue
		}
		msg, err := parseIMAPMessage(raw)
		if err != nil {
			continue
		}
		msg.AccountID = account.ID
		msg.FolderID = folder.ID
		msg.ProviderID = providerID
		msg.ThreadID = firstNonEmpty(msg.ThreadID, "imap:"+uid)
		msg.IsRead = containsIMAPFlag(flags, "\\Seen")
		msg.IsStarred = containsIMAPFlag(flags, "\\Flagged")
		msg.Labels = []string{role}
		if existing, ok := c.db.FindMessageByProvider(account.ID, msg.ProviderID); ok {
			msg.ID = existing.ID
			msg.CreatedAt = existing.CreatedAt
		}
		msg = c.db.UpsertMessage(msg)
		c.broker.Publish(model.Event{Type: "message.synced", AccountID: account.ID, MessageID: msg.ID, Payload: msg})
	}
	return nil
}

func (c IMAPSMTPConnector) Send(ctx context.Context, account model.Account, req model.SendRequest) (string, error) {
	account, err := NormalizeAccount(account)
	if err != nil {
		return "", err
	}
	if len(req.To) == 0 {
		return "", errors.New("missing recipient")
	}
	providerID := store.NewID("smtp")
	data, recipients, err := buildMIMEMessage(account, req, providerID)
	if err != nil {
		return "", err
	}
	if err := sendSMTP(ctx, account, recipients, data); err != nil {
		return "", err
	}
	sentFolder, err := folderByRole(c.db, account.ID, "sent")
	if err != nil {
		return "", err
	}
	now := time.Now()
	from := model.Address{Name: account.DisplayName, Email: account.Email}
	if req.From != nil {
		from = *req.From
	}
	msg := model.Message{
		AccountID:  account.ID,
		FolderID:   sentFolder.ID,
		ThreadID:   firstNonEmpty(req.ThreadID, providerID),
		ProviderID: providerID,
		From:       from,
		To:         req.To,
		Cc:         req.Cc,
		Bcc:        req.Bcc,
		Subject:    strings.TrimSpace(req.Subject),
		Snippet:    snippet(req.BodyText, req.BodyHTML),
		BodyText:   req.BodyText,
		BodyHTML:   req.BodyHTML,
		SentAt:     &now,
		IsRead:     true,
		Labels:     []string{"sent"},
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	msg = c.db.UpsertMessage(msg)
	c.broker.Publish(model.Event{Type: "message.sent", AccountID: account.ID, MessageID: msg.ID, Payload: msg})
	return providerID, nil
}

func NormalizeAccount(account model.Account) (model.Account, error) {
	account.Email = strings.TrimSpace(account.Email)
	account.DisplayName = strings.TrimSpace(account.DisplayName)
	account.Username = strings.TrimSpace(account.Username)
	account.IMAPHost = strings.TrimSpace(account.IMAPHost)
	account.SMTPHost = strings.TrimSpace(account.SMTPHost)
	if account.Provider == "" {
		account.Provider = model.ProviderMock
	}
	if account.DisplayName == "" {
		account.DisplayName = account.Email
	}
	if account.Username == "" {
		account.Username = account.Email
	}
	if account.Email != "" {
		if _, err := netmail.ParseAddress(account.Email); err != nil {
			return account, fmt.Errorf("invalid email address: %w", err)
		}
	}
	switch account.Provider {
	case model.ProviderMock:
		return account, nil
	case model.ProviderGmail:
		if account.IMAPHost == "" {
			account.IMAPHost = "imap.gmail.com"
		}
		if account.SMTPHost == "" {
			account.SMTPHost = "smtp.gmail.com"
		}
	case model.ProviderOutlook:
		if account.IMAPHost == "" {
			account.IMAPHost = "outlook.office365.com"
		}
		if account.SMTPHost == "" {
			account.SMTPHost = "smtp.office365.com"
		}
	case model.ProviderIMAP:
		if account.IMAPHost == "" || account.SMTPHost == "" {
			return account, errors.New("imap_host and smtp_host are required")
		}
	default:
		return account, errors.New("unsupported provider")
	}
	if account.Password == "" {
		return account, errors.New("password is required")
	}
	if account.IMAPPort == 0 {
		account.IMAPPort = 993
	}
	if account.SMTPPort == 0 {
		account.SMTPPort = 587
	}
	account.IMAPTLS = account.IMAPTLS || account.IMAPPort == 993
	account.SMTPTLS = account.SMTPTLS || account.SMTPPort == 465 || account.SMTPPort == 587
	return account, nil
}

type imapClient struct {
	conn net.Conn
	r    *bufio.Reader
	w    *bufio.Writer
	tag  int
}

func dialIMAP(ctx context.Context, account model.Account) (*imapClient, error) {
	address := net.JoinHostPort(account.IMAPHost, strconv.Itoa(account.IMAPPort))
	dialer := &net.Dialer{Timeout: 20 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", address)
	if err != nil {
		return nil, fmt.Errorf("imap connect failed: %w", err)
	}
	if account.IMAPTLS {
		tlsConn := tls.Client(conn, &tls.Config{ServerName: account.IMAPHost, MinVersion: tls.VersionTLS12})
		if err := tlsConn.HandshakeContext(ctx); err != nil {
			_ = conn.Close()
			return nil, fmt.Errorf("imap tls failed: %w", err)
		}
		conn = tlsConn
	}
	client := &imapClient{conn: conn, r: bufio.NewReader(conn), w: bufio.NewWriter(conn)}
	if _, err := client.r.ReadString('\n'); err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("imap greeting failed: %w", err)
	}
	return client, nil
}

func (c *imapClient) close() {
	_ = c.conn.Close()
}

func (c *imapClient) nextTag() string {
	c.tag++
	return fmt.Sprintf("A%04d", c.tag)
}

func (c *imapClient) command(command string, args ...any) ([]string, error) {
	tag := c.nextTag()
	if _, err := fmt.Fprintf(c.w, "%s %s\r\n", tag, fmt.Sprintf(command, args...)); err != nil {
		return nil, err
	}
	if err := c.w.Flush(); err != nil {
		return nil, err
	}
	return c.readTagged(tag)
}

func (c *imapClient) readTagged(tag string) ([]string, error) {
	var lines []string
	for {
		line, err := c.r.ReadString('\n')
		if err != nil {
			return lines, err
		}
		lines = append(lines, strings.TrimRight(line, "\r\n"))
		if strings.HasPrefix(line, tag+" ") {
			if strings.HasPrefix(line, tag+" OK") {
				return lines, nil
			}
			return lines, errors.New(strings.TrimSpace(line))
		}
	}
}

func (c *imapClient) login(username, password string) error {
	_, err := c.command("LOGIN %s %s", imapQuote(username), imapQuote(password))
	return err
}

func (c *imapClient) selectMailbox(name string) error {
	_, err := c.command("SELECT %s", imapQuote(name))
	return err
}

func (c *imapClient) searchAll() ([]string, error) {
	lines, err := c.command("UID SEARCH ALL")
	if err != nil {
		return nil, err
	}
	for _, line := range lines {
		if strings.HasPrefix(line, "* SEARCH") {
			fields := strings.Fields(strings.TrimPrefix(line, "* SEARCH"))
			return fields, nil
		}
	}
	return nil, nil
}

func (c *imapClient) searchSince(t time.Time) ([]string, error) {
	dateStr := t.Format("02-Jan-2006")
	lines, err := c.command("UID SEARCH SINCE %s", dateStr)
	if err != nil {
		return nil, err
	}
	for _, line := range lines {
		if strings.HasPrefix(line, "* SEARCH") {
			fields := strings.Fields(strings.TrimPrefix(line, "* SEARCH"))
			return fields, nil
		}
	}
	return nil, nil
}

func (c *imapClient) fetchRFC822(uid string) ([]byte, string, error) {
	tag := c.nextTag()
	if _, err := fmt.Fprintf(c.w, "%s UID FETCH %s (FLAGS RFC822)\r\n", tag, uid); err != nil {
		return nil, "", err
	}
	if err := c.w.Flush(); err != nil {
		return nil, "", err
	}
	var raw []byte
	var flags string
	for {
		line, err := c.r.ReadString('\n')
		if err != nil {
			return raw, flags, err
		}
		if strings.Contains(line, "FLAGS") {
			flags = line
		}
		if size, ok := literalSize(line); ok {
			limit := size
			if limit > maxIMAPMessageBytes {
				limit = maxIMAPMessageBytes
			}
			raw = make([]byte, limit)
			if _, err := io.ReadFull(c.r, raw); err != nil {
				return raw, flags, err
			}
			if size > limit {
				if _, err := io.CopyN(io.Discard, c.r, int64(size-limit)); err != nil {
					return raw, flags, err
				}
			}
			continue
		}
		if strings.HasPrefix(line, tag+" ") {
			if strings.HasPrefix(line, tag+" OK") {
				return raw, flags, nil
			}
			return raw, flags, errors.New(strings.TrimSpace(line))
		}
	}
}

func (c *imapClient) logout() error {
	_, err := c.command("LOGOUT")
	return err
}

func imapQuote(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, `"`, `\"`)
	return `"` + value + `"`
}

func literalSize(line string) (int, bool) {
	match := literalPattern.FindStringSubmatch(line)
	if len(match) != 2 {
		return 0, false
	}
	size, err := strconv.Atoi(match[1])
	return size, err == nil
}

func parseIMAPMessage(raw []byte) (model.Message, error) {
	message, err := netmail.ReadMessage(bytes.NewReader(raw))
	if err != nil {
		return model.Message{}, err
	}
	header := message.Header
	subject, _ := (&mime.WordDecoder{}).DecodeHeader(header.Get("Subject"))
	from := parseAddress(header.Get("From"))
	to := parseAddressList(header.Get("To"))
	cc := parseAddressList(header.Get("Cc"))
	date := time.Now()
	if parsedDate, err := header.Date(); err == nil {
		date = parsedDate
	}
	body, _ := io.ReadAll(io.LimitReader(message.Body, maxIMAPMessageBytes))
	text, htmlBody := parseBodyParts(header, body)
	if text == "" {
		text = stripTags(htmlBody)
	}
	if htmlBody == "" && looksLikeHTML(text) {
		htmlBody = text
		text = stripTags(text)
	}
	return model.Message{
		From:       from,
		To:         to,
		Cc:         cc,
		Subject:    firstNonEmpty(subject, "(无主题)"),
		Snippet:    snippet(text, htmlBody),
		BodyText:   text,
		BodyHTML:   htmlBody,
		ReceivedAt: &date,
	}, nil
}

type mimeHeader interface {
	Get(string) string
}

func parseBodyParts(header mimeHeader, body []byte) (string, string) {
	contentType := header.Get("Content-Type")
	mediaType, params, err := mime.ParseMediaType(contentType)
	if err != nil || mediaType == "" {
		return decodeTransfer(header.Get("Content-Transfer-Encoding"), body), ""
	}
	mediaType = strings.ToLower(mediaType)
	if strings.HasPrefix(mediaType, "multipart/") {
		reader := multipart.NewReader(bytes.NewReader(body), params["boundary"])
		var textBody string
		var htmlBody string
		for {
			part, err := reader.NextPart()
			if errors.Is(err, io.EOF) {
				break
			}
			if err != nil {
				break
			}
			partBody, _ := io.ReadAll(io.LimitReader(part, maxIMAPMessageBytes))
			partText, partHTML := parseBodyParts(textproto.MIMEHeader(part.Header), partBody)
			if textBody == "" {
				textBody = partText
			}
			if htmlBody == "" {
				htmlBody = partHTML
			}
		}
		return textBody, htmlBody
	}
	decoded := decodeTransfer(header.Get("Content-Transfer-Encoding"), body)
	switch mediaType {
	case "text/plain":
		return strings.TrimSpace(decoded), ""
	case "text/html":
		return "", decoded
	default:
		return "", ""
	}
}

func decodeTransfer(encoding string, body []byte) string {
	switch strings.ToLower(strings.TrimSpace(encoding)) {
	case "base64":
		decoded, err := io.ReadAll(base64.NewDecoder(base64.StdEncoding, bytes.NewReader(body)))
		if err == nil {
			return strings.TrimSpace(string(decoded))
		}
	case "quoted-printable":
		decoded, err := io.ReadAll(quotedprintable.NewReader(bytes.NewReader(body)))
		if err == nil {
			return strings.TrimSpace(string(decoded))
		}
	}
	return strings.TrimSpace(string(body))
}

func parseAddress(value string) model.Address {
	addr, err := netmail.ParseAddress(value)
	if err != nil {
		return model.Address{Email: strings.TrimSpace(value)}
	}
	name, _ := (&mime.WordDecoder{}).DecodeHeader(addr.Name)
	return model.Address{Name: name, Email: addr.Address}
}

func parseAddressList(value string) []model.Address {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	list, err := netmail.ParseAddressList(value)
	if err != nil {
		return []model.Address{{Email: strings.TrimSpace(value)}}
	}
	out := make([]model.Address, 0, len(list))
	for _, addr := range list {
		name, _ := (&mime.WordDecoder{}).DecodeHeader(addr.Name)
		out = append(out, model.Address{Name: name, Email: addr.Address})
	}
	return out
}

func containsIMAPFlag(flags, flag string) bool {
	return strings.Contains(strings.ToLower(flags), strings.ToLower(flag))
}

func looksLikeHTML(value string) bool {
	lower := strings.ToLower(value)
	return strings.Contains(lower, "<html") || strings.Contains(lower, "<body") || strings.Contains(lower, "<p>")
}

func folderByRole(db *store.Memory, accountID, role string) (model.Folder, error) {
	for _, folder := range db.ListFolders(accountID) {
		if folder.Role == role {
			return folder, nil
		}
	}
	return model.Folder{}, fmt.Errorf("%s folder not found", role)
}

func buildMIMEMessage(account model.Account, req model.SendRequest, providerID string) ([]byte, []string, error) {
	from := model.Address{Name: account.DisplayName, Email: account.Email}
	if req.From != nil {
		from = *req.From
	}
	recipients := append([]model.Address{}, req.To...)
	recipients = append(recipients, req.Cc...)
	recipients = append(recipients, req.Bcc...)
	if len(recipients) == 0 {
		return nil, nil, errors.New("missing recipient")
	}
	var recipientEmails []string
	for _, recipient := range recipients {
		if _, err := netmail.ParseAddress(recipient.Email); err != nil {
			return nil, nil, fmt.Errorf("invalid recipient %q: %w", recipient.Email, err)
		}
		recipientEmails = append(recipientEmails, recipient.Email)
	}
	var b strings.Builder
	writeHeader(&b, "From", formatAddress(from))
	writeHeader(&b, "To", formatAddressList(req.To))
	if len(req.Cc) > 0 {
		writeHeader(&b, "Cc", formatAddressList(req.Cc))
	}
	writeHeader(&b, "Subject", mime.QEncoding.Encode("utf-8", strings.TrimSpace(req.Subject)))
	writeHeader(&b, "Date", time.Now().Format(time.RFC1123Z))
	writeHeader(&b, "Message-ID", fmt.Sprintf("<%s@%s>", providerID, domainFromEmail(account.Email)))
	writeHeader(&b, "MIME-Version", "1.0")
	if req.BodyHTML == "" {
		writeHeader(&b, "Content-Type", "text/plain; charset=utf-8")
		writeHeader(&b, "Content-Transfer-Encoding", "8bit")
		b.WriteString("\r\n")
		b.WriteString(req.BodyText)
		return []byte(b.String()), recipientEmails, nil
	}
	boundary := "mail-" + providerID
	writeHeader(&b, "Content-Type", `multipart/alternative; boundary="`+boundary+`"`)
	b.WriteString("\r\n")
	b.WriteString("--" + boundary + "\r\n")
	b.WriteString("Content-Type: text/plain; charset=utf-8\r\n")
	b.WriteString("Content-Transfer-Encoding: 8bit\r\n\r\n")
	b.WriteString(req.BodyText)
	b.WriteString("\r\n--" + boundary + "\r\n")
	b.WriteString("Content-Type: text/html; charset=utf-8\r\n")
	b.WriteString("Content-Transfer-Encoding: 8bit\r\n\r\n")
	b.WriteString(req.BodyHTML)
	b.WriteString("\r\n--" + boundary + "--\r\n")
	return []byte(b.String()), recipientEmails, nil
}

func sendSMTP(ctx context.Context, account model.Account, recipients []string, data []byte) error {
	address := net.JoinHostPort(account.SMTPHost, strconv.Itoa(account.SMTPPort))
	dialer := &net.Dialer{Timeout: 20 * time.Second}
	var conn net.Conn
	var err error
	if account.SMTPTLS && account.SMTPPort == 465 {
		conn, err = tls.DialWithDialer(dialer, "tcp", address, &tls.Config{ServerName: account.SMTPHost, MinVersion: tls.VersionTLS12})
	} else {
		conn, err = dialer.DialContext(ctx, "tcp", address)
	}
	if err != nil {
		return fmt.Errorf("smtp connect failed: %w", err)
	}
	client, err := smtp.NewClient(conn, account.SMTPHost)
	if err != nil {
		_ = conn.Close()
		return err
	}
	defer client.Close()
	if account.SMTPTLS && account.SMTPPort != 465 {
		if ok, _ := client.Extension("STARTTLS"); !ok {
			return errors.New("smtp server does not support STARTTLS")
		}
		if err := client.StartTLS(&tls.Config{ServerName: account.SMTPHost, MinVersion: tls.VersionTLS12}); err != nil {
			return fmt.Errorf("smtp starttls failed: %w", err)
		}
	}
	if account.Username != "" && account.Password != "" {
		if ok, _ := client.Extension("AUTH"); ok {
			if err := client.Auth(smtp.PlainAuth("", account.Username, account.Password, account.SMTPHost)); err != nil {
				return fmt.Errorf("smtp auth failed: %w", err)
			}
		}
	}
	if err := client.Mail(account.Email); err != nil {
		return err
	}
	for _, recipient := range recipients {
		if err := client.Rcpt(recipient); err != nil {
			return err
		}
	}
	writer, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := writer.Write(data); err != nil {
		_ = writer.Close()
		return err
	}
	if err := writer.Close(); err != nil {
		return err
	}
	return client.Quit()
}

func writeHeader(b *strings.Builder, key, value string) {
	if strings.TrimSpace(value) == "" {
		return
	}
	b.WriteString(key)
	b.WriteString(": ")
	b.WriteString(value)
	b.WriteString("\r\n")
}

func formatAddress(address model.Address) string {
	return (&netmail.Address{Name: address.Name, Address: address.Email}).String()
}

func formatAddressList(addresses []model.Address) string {
	values := make([]string, 0, len(addresses))
	for _, address := range addresses {
		values = append(values, formatAddress(address))
	}
	return strings.Join(values, ", ")
}

func domainFromEmail(email string) string {
	parts := strings.Split(email, "@")
	if len(parts) == 2 && strings.TrimSpace(parts[1]) != "" {
		return parts[1]
	}
	return "localhost"
}
