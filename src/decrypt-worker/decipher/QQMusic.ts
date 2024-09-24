import { DecipherInstance, DecipherOK, DecipherResult, Status } from '~/decrypt-worker/Deciphers';
import { decryptQMC1, QMC2, QMCFooter } from '@unlock-music/crypto';
import { chunkBuffer } from '~/decrypt-worker/util/buffer.ts';
import type { DecryptCommandOptions } from '~/decrypt-worker/types.ts';
import { UnsupportedSourceFile } from '~/decrypt-worker/util/DecryptError.ts';
import { isDataLooksLikeAudio } from '~/decrypt-worker/util/audioType.ts';

export class QQMusicV1Decipher implements DecipherInstance {
  cipherName = 'QQMusic/QMC1';

  async decrypt(buffer: Uint8Array): Promise<DecipherResult | DecipherOK> {
    const header = buffer.slice(0, 0x20);
    decryptQMC1(header, 0);
    if (!isDataLooksLikeAudio(header)) {
      throw new UnsupportedSourceFile('does not look like QMC file');
    }

    const audioBuffer = new Uint8Array(buffer);
    for (const [block, offset] of chunkBuffer(audioBuffer)) {
      decryptQMC1(block, offset);
    }
    return {
      status: Status.OK,
      cipherName: this.cipherName,
      data: audioBuffer,
    };
  }

  public static create() {
    return new QQMusicV1Decipher();
  }
}

export class QQMusicV2Decipher implements DecipherInstance {
  cipherName: string;

  constructor(private readonly useUserKey: boolean) {
    this.cipherName = `QQMusic/QMC2(user_key=${+useUserKey})`;
  }

  async decrypt(buffer: Uint8Array, options: DecryptCommandOptions): Promise<DecipherResult | DecipherOK> {
    const footer = QMCFooter.parse(buffer.subarray(buffer.byteLength - 1024));
    if (!footer) {
      throw new UnsupportedSourceFile('Not QMC2 File');
    }

    const audioBuffer = buffer.slice(0, buffer.byteLength - footer.size);
    const ekey = this.useUserKey ? options.qmc2Key : footer.ekey;
    footer.free();
    if (!ekey) {
      throw new Error('EKey missing');
    }

    const qmc2 = new QMC2(ekey);
    for (const [block, offset] of chunkBuffer(audioBuffer)) {
      qmc2.decrypt(block, offset);
    }
    qmc2.free();

    return {
      status: Status.OK,
      cipherName: this.cipherName,
      data: audioBuffer,
    };
  }

  public static createWithUserKey() {
    return new QQMusicV2Decipher(true);
  }

  public static createWithEmbeddedEKey() {
    return new QQMusicV2Decipher(false);
  }
}
