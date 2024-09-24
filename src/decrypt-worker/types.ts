export interface DecryptCommandOptions {
  fileName: string;
  qmc2Key?: string;
  kwm2key?: string;
  qingTingAndroidKey?: string;
}

export interface DecryptCommandPayload {
  id: string;
  blobURI: string;
  options: DecryptCommandOptions;
}

export interface FetchMusicExNamePayload {
  blobURI: string;
}

export interface ParseKuwoHeaderPayload {
  blobURI: string;
}

export type ParseKuwoHeaderResponse = null | {
  resourceId: number;
  qualityId: number;
};

export interface GetQingTingFMDeviceKeyPayload {
  product: string;
  device: string;
  manufacturer: string;
  brand: string;
  board: string;
  model: string;
}
