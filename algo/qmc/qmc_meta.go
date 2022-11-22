package qmc

import (
	"context"
	"errors"
	"fmt"

	"unlock-music.dev/cli/algo/common"
	"unlock-music.dev/cli/algo/qmc/client"
)

func (d *Decoder) GetAudioMeta(ctx context.Context) (common.AudioMeta, error) {
	if d.meta != nil {
		return d.meta, nil
	}

	if d.songID != 0 {
		return d.meta, d.getMetaBySongID(ctx)
	}

	return nil, errors.New("qmc[GetAudioMeta] not implemented")
}

func (d *Decoder) getMetaBySongID(ctx context.Context) error {
	c := client.NewQQMusicClient() // todo: use global client
	trackInfo, err := c.GetTrackInfo(ctx, d.songID)
	if err != nil {
		return fmt.Errorf("qmc[GetAudioMeta] get track info: %w", err)
	}

	d.meta = trackInfo
	d.albumID = trackInfo.Album.Id
	if trackInfo.Album.Pmid == "" {
		d.albumMediaID = trackInfo.Album.Pmid
	} else {
		d.albumMediaID = trackInfo.Album.Mid
	}
	return nil
}

func (d *Decoder) GetCoverImage(ctx context.Context) ([]byte, error) {
	if d.cover != nil {
		return d.cover, nil
	}

	// todo: get meta if possible
	c := client.NewQQMusicClient() // todo: use global client
	var err error

	if d.albumMediaID != "" {
		d.cover, err = c.AlbumCoverByMediaID(ctx, d.albumMediaID)
		if err != nil {
			return nil, fmt.Errorf("qmc[GetCoverImage] get cover by media id: %w", err)
		}
	} else if d.albumID != 0 {
		d.cover, err = c.AlbumCoverByID(ctx, d.albumID)
		if err != nil {
			return nil, fmt.Errorf("qmc[GetCoverImage] get cover by id: %w", err)
		}
	} else {
		return nil, errors.New("qmc[GetAudioMeta] album (or media) id is empty")
	}

	return d.cover, nil
}
