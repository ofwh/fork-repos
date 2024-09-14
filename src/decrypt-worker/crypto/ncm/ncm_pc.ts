import type { CryptoBase } from '../CryptoBase';
import { NCMFile } from '@unlock-music/crypto';
import { chunkBuffer } from '~/decrypt-worker/util/buffer.ts';

export class NCMCrypto implements CryptoBase {
  cryptoName = 'NCM/PC';
  checkByDecryptHeader = false;
  ncm = new NCMFile();

  async checkBySignature(buffer: ArrayBuffer) {
    try {
      this.ncm.open(new Uint8Array(buffer));
    } catch (error) {
      return false;
    }
    return true;
  }

  async decrypt(buffer: ArrayBuffer): Promise<Blob> {
    const audioBuffer = new Uint8Array(buffer.slice(this.ncm.audioOffset));
    for (const [block, offset] of chunkBuffer(audioBuffer)) {
      this.ncm.decrypt(block, offset);
    }
    return new Blob([audioBuffer]);
  }

  public static make() {
    return new NCMCrypto();
  }
}
