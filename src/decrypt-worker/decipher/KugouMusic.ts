import { DecipherInstance, DecipherOK, DecipherResult, Status } from '~/decrypt-worker/Deciphers';
import { KuGou } from '@unlock-music/crypto';
import type { DecryptCommandOptions } from '~/decrypt-worker/types.ts';
import { chunkBuffer } from '~/decrypt-worker/util/buffer.ts';

export class KugouMusicDecipher implements DecipherInstance {
  cipherName = 'Kugou';

  async decrypt(buffer: Uint8Array, _options: DecryptCommandOptions): Promise<DecipherResult | DecipherOK> {
    let kgm: KuGou | undefined;

    try {
      kgm = KuGou.from_header(buffer.subarray(0, 0x400));

      const audioBuffer = new Uint8Array(buffer.subarray(0x400));
      for (const [block, offset] of chunkBuffer(audioBuffer)) {
        kgm.decrypt(block, offset);
      }

      return {
        status: Status.OK,
        cipherName: this.cipherName,
        data: audioBuffer,
      };
    } finally {
      kgm?.free();
    }
  }

  public static make() {
    return new KugouMusicDecipher();
  }
}
