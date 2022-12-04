package qmc

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"unlock-music.dev/mmkv"
)

var streamKeyVault mmkv.Vault

func readKeyFromMMKV(file string) ([]byte, error) {
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
	}

	buf, err := streamKeyVault.GetBytes(file)
	if err != nil { // fallback match filename only
		_, partName := filepath.Split(file)
		keys := streamKeyVault.Keys()
		for _, key := range keys {
			if !strings.HasSuffix(key, partName) {
				continue
			}
			buf, err = streamKeyVault.GetBytes(key)
			if err != nil {
				// TODO: logger
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
