package openmesh

import bip39 "github.com/tyler-smith/go-bip39"

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

func (a *AppLib) GenerateMnemonic12() (string, error) {
	entropy, err := bip39.NewEntropy(128)
	if err != nil {
		return "", err
	}
	return bip39.NewMnemonic(entropy)
}
