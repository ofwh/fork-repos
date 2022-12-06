package ffmpeg

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"unlock-music.dev/cli/algo/common"
	"unlock-music.dev/cli/internal/utils"
)

func ExtractAlbumArt(ctx context.Context, rd io.Reader) (*bytes.Buffer, error) {
	cmd := exec.CommandContext(ctx, "ffmpeg",
		"-i", "pipe:0", // input from stdin
		"-an",              // disable audio
		"-codec:v", "copy", // copy video(image) codec
		"-f", "image2", // use image2 muxer
		"pipe:1", // output to stdout
	)

	cmd.Stdin = rd
	stdout, stderr := &bytes.Buffer{}, &bytes.Buffer{}
	cmd.Stdout, cmd.Stderr = stdout, stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("ffmpeg run: %w", err)
	}

	return stdout, nil
}

type UpdateMetadataParams struct {
	Audio    string // required
	AudioExt string // required

	Meta common.AudioMeta // required

	AlbumArt    io.Reader // optional
	AlbumArtExt string    // required if AlbumArt is not nil
}

func UpdateAudioMetadata(ctx context.Context, outPath string, params *UpdateMetadataParams) error {
	builder := newFFmpegBuilder()

	out := newOutputBuilder(outPath) // output to file
	builder.SetFlag("y")             // overwrite output file
	builder.AddOutput(out)

	// input audio -> output audio
	builder.AddInput(newInputBuilder(params.Audio)) // input 0: audio
	out.AddOption("map", "0:a")
	out.AddOption("codec:a", "copy")

	// input cover -> output cover
	if params.AlbumArt != nil &&
		params.AudioExt != ".wav" /* wav doesn't support attached image */ {

		// write cover to temp file
		artPath, err := utils.WriteTempFile(params.AlbumArt, params.AlbumArtExt)
		if err != nil {
			return fmt.Errorf("updateAudioMeta write temp file: %w", err)
		}
		defer os.Remove(artPath)

		builder.AddInput(newInputBuilder(artPath)) // input 1: cover
		out.AddOption("map", "1:v")

		switch params.AudioExt {
		case ".ogg": // ogg only supports theora codec
			out.AddOption("codec:v", "libtheora")
		case ".m4a": // .m4a(mp4) requires set codec, disposition, stream metadata
			out.AddOption("codec:v", "mjpeg")
			out.AddOption("disposition:v", "attached_pic")
			out.AddMetadata("s:v", "title", "Album cover")
			out.AddMetadata("s:v", "comment", "Cover (front)")
		default: // other formats use default behavior
		}
	}

	// set file metadata
	album := params.Meta.GetAlbum()
	if album != "" {
		out.AddMetadata("", "album", album)
	}

	title := params.Meta.GetTitle()
	if album != "" {
		out.AddMetadata("", "title", title)
	}

	artists := params.Meta.GetArtists()
	if len(artists) != 0 {
		// TODO: it seems that ffmpeg doesn't support multiple artists
		out.AddMetadata("", "artist", strings.Join(artists, " / "))
	}

	// execute ffmpeg
	cmd := builder.Command(ctx)

	if stdout, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg run: %w, %s", err, string(stdout))
	}

	return nil
}
