package store

import "context"

type UserStoreAdapter struct {
	pg *Postgres
}

func NewUserStoreAdapter(pg *Postgres) *UserStoreAdapter {
	return &UserStoreAdapter{pg: pg}
}

func (a *UserStoreAdapter) GetUserByEmail(email string) (id, passwordHash, role string, err error) {
	return a.pg.GetUserByEmail(context.Background(), email)
}

func (a *UserStoreAdapter) HasUsers() (bool, error) {
	return a.pg.HasUsers(context.Background())
}

func (a *UserStoreAdapter) CreateUser(email, passwordHash, role string) (string, error) {
	return a.pg.CreateUser(context.Background(), email, passwordHash, role)
}
