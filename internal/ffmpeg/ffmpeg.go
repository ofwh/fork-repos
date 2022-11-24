package ffmpeg

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os/exec"
)

func ExtractAlbumArt(ctx context.Context, rd io.Reader) (io.Reader, error) {
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

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("ffmpeg run: %w", err)
	}

	if err := cmd.Wait(); err != nil {
		return nil, fmt.Errorf("ffmpeg wait: %w: %s", err, stderr.String())
	}

	return stdout, nil
}
