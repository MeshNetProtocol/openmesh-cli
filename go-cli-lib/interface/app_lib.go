package openmesh

type AppLib struct {
	config []byte
}

func NewLib() *AppLib {
	return &AppLib{}
}

func (a *AppLib) InitApp(config []byte) error {
	a.config = append([]byte(nil), config...)
	return nil
}
