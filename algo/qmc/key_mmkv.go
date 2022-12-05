package qmc

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/hbollon/go-edlib"
	"github.com/samber/lo"
	"go.uber.org/zap"
	"golang.org/x/exp/slices"
	"unlock-music.dev/mmkv"
)

var streamKeyVault mmkv.Vault

// TODO: move to factory
func readKeyFromMMKV(file string, logger *zap.Logger) ([]byte, error) {
	if file == "" {
		return nil, errors.New("file path is required while reading key from mmkv")
	}

	//goland:noinspection GoBoolExpressions
	if runtime.GOOS != "darwin" {
		return nil, errors.New("mmkv vault not supported on this platform")
	}

	if streamKeyVault == nil {
		mmkvDir, err := getRelativeMMKVDir(file)
		if err != nil {
			mmkvDir, err = getDefaultMMKVDir()
			if err != nil {
				return nil, fmt.Errorf("mmkv key valut not found: %w", err)
			}
		}

		mgr, err := mmkv.NewManager(mmkvDir)
		if err != nil {
			return nil, fmt.Errorf("init mmkv manager: %w", err)
		}

		streamKeyVault, err = mgr.OpenVault("MMKVStreamEncryptId")
		if err != nil {
			return nil, fmt.Errorf("open mmkv vault: %w", err)
		}

		logger.Debug("mmkv vault opened", zap.Strings("keys", streamKeyVault.Keys()))
	}

	_, partName := filepath.Split(file)
	buf, err := streamKeyVault.GetBytes(file)

	if buf == nil {
		filePaths := streamKeyVault.Keys()

		for _, key := range filePaths { // fallback 1: match filename only
			if !strings.HasSuffix(key, partName) {
				continue
			}
			buf, err = streamKeyVault.GetBytes(key)
			if err != nil {
				logger.Warn("read key from mmkv", zap.String("key", key), zap.Error(err))
			}
		}

		if buf == nil { // fallback 2: match filename with edit distance
			// use editorial judgement to select the best match
			//     since macOS may change some characters in the file name.
			//     e.g. "ぜ"(e3 81 9c) -> "ぜ"(e3 81 9b e3 82 99)
			fileNames := lo.Map(filePaths, func(filePath string, _ int) string {
				_, name := filepath.Split(filePath)
				return name
			})

			minDisStr, err := edlib.FuzzySearch(partName, fileNames, edlib.Levenshtein)
			if err != nil {
				logger.Warn("fuzzy search failed", zap.Error(err))
			}

			// TODO: make distance configurable
			// for now, assume only 1 character changed to 2 characters
			if edlib.LevenshteinDistance(partName, minDisStr) < 3 {
				idx := slices.Index(fileNames, minDisStr)
				buf, err = streamKeyVault.GetBytes(filePaths[idx])
				if err != nil {
					logger.Warn("read key from mmkv", zap.String("key", minDisStr), zap.Error(err))
				}
			}
		}
	}

	if len(buf) == 0 {
		return nil, errors.New("key not found in mmkv vault")
	}

	return deriveKey(buf)
}

func getRelativeMMKVDir(file string) (string, error) {
	mmkvDir := filepath.Join(filepath.Dir(file), "../mmkv")
	if _, err := os.Stat(mmkvDir); err != nil {
		return "", fmt.Errorf("stat default mmkv dir: %w", err)
	}

	keyFile := filepath.Join(mmkvDir, "MMKVStreamEncryptId")
	if _, err := os.Stat(keyFile); err != nil {
		return "", fmt.Errorf("stat default mmkv file: %w", err)
	}

	return mmkvDir, nil
}

func getDefaultMMKVDir() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("get user home dir: %w", err)
	}

	mmkvDir := filepath.Join(
		homeDir,
		"Library/Containers/com.tencent.QQMusicMac/Data", // todo: make configurable
		"Library/Application Support/QQMusicMac/mmkv",
	)
	if _, err := os.Stat(mmkvDir); err != nil {
		return "", fmt.Errorf("stat default mmkv dir: %w", err)
	}

	keyFile := filepath.Join(mmkvDir, "MMKVStreamEncryptId")
	if _, err := os.Stat(keyFile); err != nil {
		return "", fmt.Errorf("stat default mmkv file: %w", err)
	}

	return mmkvDir, nil
}
