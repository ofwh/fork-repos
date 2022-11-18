package kgm

import (
	"fmt"
	"io"

	"github.com/unlock-music/cli/algo/common"
)

type Decoder struct {
	header header
	cipher common.StreamDecoder

	rd     io.ReadSeeker
	offset int
}

func NewDecoder(rd io.ReadSeeker) common.Decoder {
	return &Decoder{rd: rd}
}

var kgmCryptoInitializers = map[uint32]func(header *header) (common.StreamDecoder, error){
	3: newKgmCryptoV3,
}

func (d *Decoder) Validate() error {
	if err := d.header.FromFile(d.rd); err != nil {
		return err
	}
	// TODO; validate crypto version

	initializer, ok := kgmCryptoInitializers[d.header.CryptoVersion]
	if !ok {
		return fmt.Errorf("kgm: unsupported crypto version %d", d.header.CryptoVersion)
	}

	var err error
	d.cipher, err = initializer(&d.header)
	if err != nil {
		return fmt.Errorf("kgm: failed to initialize crypto: %w", err)
	}

	return nil
}

func (d *Decoder) Read(buf []byte) (int, error) {
	n, err := d.rd.Read(buf)
	if n > 0 {
		d.cipher.Decrypt(buf[:n], d.offset)
		d.offset += n
	}
	return n, err
}

func init() {
	// Kugou
	common.RegisterDecoder("kgm", false, NewDecoder)
	common.RegisterDecoder("kgma", false, NewDecoder)
	// Viper
	common.RegisterDecoder("vpr", false, NewDecoder)
}
