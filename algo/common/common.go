package common

import "context"

type Decoder interface {
	Validate() error
	Decode() error
	GetAudioData() []byte
	GetAudioExt() string
	GetMeta() Meta
}

type CoverImageGetter interface {
	GetCoverImage(ctx context.Context) ([]byte, error)
}

type Meta interface {
	GetArtists() []string
	GetTitle() string
	GetAlbum() string
}
