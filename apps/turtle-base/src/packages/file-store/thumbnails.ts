/** Longest edge of a thumbnail - enough for grid cells, tiles and high-density lists; full views use the original. */
export const thumbnailMaxEdge = 512;

/** Larger images aren't decoded for a thumbnail: the decoded pixels would take several times the file size in memory. */
export const thumbnailMaxSourceBytes = 50 * 1024 * 1024;

export interface Thumbnail {
  readonly jpeg: Uint8Array;

  /** Of the original image, with its EXIF orientation applied - so a portrait phone photo is portrait in both. */
  readonly width: number;
  readonly height: number;
}

/** Makes thumbnails of images - undefined for content it can't decode. */
export type ThumbnailMaker = (image: Blob) => Promise<Thumbnail | undefined>;

/**
 * Thumbnails through the web view's own image decoding: whatever it can
 * show, it can shrink. `createImageBitmap` applies the EXIF orientation.
 */
export const browserThumbnailMaker: ThumbnailMaker = async (image) => {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(image);
  } catch {
    return undefined;
  }
  try {
    const { width, height } = bitmap;
    const scale = Math.min(1, thumbnailMaxEdge / Math.max(width, height));
    const canvas = new OffscreenCanvas(Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale)));
    const context = canvas.getContext('2d');
    if (context === null) return undefined;
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const jpeg = await canvas.convertToBlob({ type: 'image/jpeg', quality: 0.8 });
    return { jpeg: new Uint8Array(await jpeg.arrayBuffer()), width, height };
  } finally {
    bitmap.close();
  }
};
