import type { CryptoBase } from '../CryptoBase';
import { NCMFile } from '@unlock-music/crypto';
import { chunkBuffer } from '~/decrypt-worker/util/buffer.ts';

export class NCMCrypto implements CryptoBase {
  cryptoName = 'NCM/PC';
  checkByDecryptHeader = false;
  ncm = new NCMFile();

  async checkBySignature(buffer: ArrayBuffer) {
    const data = new Uint8Array(buffer);
    let len = 1024;
    try {
      while (len !== 0) {
        console.debug('NCM/open: read %d bytes', len);
        len = this.ncm.open(data.subarray(0, len));
      }
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
