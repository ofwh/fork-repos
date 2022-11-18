package kgm

import (
	"bytes"
	"fmt"
	"io"

	"github.com/unlock-music/cli/algo/common"
)

type Decoder struct {
	header      Header
	initializer kgmCryptoInitializer

	file  []byte
	audio []byte
}

type kgmCryptoInitializer func(header *Header, body io.Reader) (io.Reader, error)

var kgmCryptoInitializers = map[uint32]kgmCryptoInitializer{
	3: newKgmCryptoV3,
}

func NewDecoder(file []byte) common.Decoder {
	return &Decoder{
		file: file,
	}
}

func (d *Decoder) GetAudioData() []byte {
	return d.audio
}

func (d *Decoder) GetAudioExt() string {
	return "" // use sniffer
}

func (d *Decoder) GetMeta() common.Meta {
	return nil
}

func (d *Decoder) Validate() error {
	if err := d.header.FromBytes(d.file); err != nil {
		return err
	}
	// TODO; validate crypto version

	var ok bool
	d.initializer, ok = kgmCryptoInitializers[d.header.CryptoVersion]
	if !ok {
		return fmt.Errorf("kgm: unsupported crypto version %d", d.header.CryptoVersion)
	}

	return nil
}

func (d *Decoder) Decode() error {
	d.audio = d.file[d.header.AudioOffset:]

	r, err := d.initializer(&d.header, bytes.NewReader(d.audio))
	if err != nil {
		return fmt.Errorf("kgm: failed to initialize crypto: %w", err)
	}
	d.audio, err = io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("kgm: failed to decrypt audio: %w", err)
	}
	return nil
}

func init() {
	// Kugou
	common.RegisterDecoder("kgm", false, NewDecoder)
	common.RegisterDecoder("kgma", false, NewDecoder)
	// Viper
	common.RegisterDecoder("vpr", false, NewDecoder)
}
