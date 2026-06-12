# Self-hosted Mail Client

Flutter cross-platform client for the self-hosted mail backend.

## Run

```bash
flutter pub get
flutter run -d windows
```

## Connect to a backend

On the login screen, set the service URL to your backend origin, for example:

```text
https://mail.example.com
```

Do not include `/api/v1`; the client appends API paths automatically.
