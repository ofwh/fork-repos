package common

import (
	"context"
	"io"
)

type Decoder interface {
	Validate() error
	io.Reader
}

type CoverImageGetter interface {
	GetCoverImage(ctx context.Context) ([]byte, error)
}

type Meta interface {
	GetArtists() []string
	GetTitle() string
	GetAlbum() string
}

type StreamDecoder interface {
	Decrypt(buf []byte, offset int)
}
