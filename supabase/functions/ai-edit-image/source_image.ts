// Reading a JPEG's structure without decoding it.
//
// OpenAI's image edit endpoint rejected some photographs outright with
// "Invalid image file or mode for image 1" while accepting others, including
// far larger ones — an 8000x6000 source edited fine, a 4284x5712 one did not.
// Neither the pixel count, the aspect ratio, nor the size we requested
// separated the two groups. What separated them was everything wrapped around
// the pixels: the failures were Apple HDR photographs carrying an EXIF block,
// an XMP block, a colour profile split across several segments, and an APP10
// marker holding the gain map. The images that worked were plain JPEGs.
//
// The functions here read that structure so the caller can decide whether a
// photograph needs rebuilding before it is sent somewhere fussier than a
// browser. None of them decode pixels; they walk the segment list, which is
// cheap enough to run on every edit regardless of how large the file is.

/** JPEG markers that carry no segment payload and so have no length field. */
const standaloneMarkers = new Set([
  0xd8, // SOI
  0xd9, // EOI
  0x01, // TEM
]);

/** Start-of-frame markers, which is where the real pixel dimensions live. */
const frameMarkers = new Set([
  0xc0, 0xc1, 0xc2, 0xc3,
  0xc5, 0xc6, 0xc7,
  0xc9, 0xca, 0xcb,
  0xcd, 0xce, 0xcf,
]);

export interface JpegProfile {
  /** Width as the pixels are actually stored, before any EXIF rotation. */
  readonly frameWidth: number;
  /** Height as the pixels are actually stored, before any EXIF rotation. */
  readonly frameHeight: number;
  /** EXIF orientation, 1..8. Defaults to 1 when absent or unreadable. */
  readonly orientation: number;
  /** Every APPn marker number found, in order of appearance. */
  readonly appMarkers: readonly number[];
  /** How many APP2 segments carry an ICC profile. */
  readonly iccSegments: number;
  /** Whether the pixels are stored rotated relative to how they display. */
  readonly isRotated: boolean;
  /**
   * Whether this file should be rebuilt before being handed to a decoder we
   * do not control.
   */
  readonly needsRebuild: boolean;
}

/**
 * Reads a JPEG's frame size, orientation and marker inventory.
 *
 * Returns null for anything that is not a JPEG, which the caller should treat
 * as "leave it alone" rather than as an error: PNG and WebP sources have never
 * been rejected, and guessing at them would risk breaking what already works.
 */
export function inspectJpeg(bytes: Uint8Array): JpegProfile | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const appMarkers: number[] = [];
  let iccSegments = 0;
  let orientation = 1;
  let frameWidth = 0;
  let frameHeight = 0;

  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) {
      offset += 1;
      continue;
    }

    const marker = bytes[offset + 1];

    // Padding between segments is legal and encoded as repeated 0xFF bytes.
    if (marker === 0xff) {
      offset += 1;
      continue;
    }
    if (standaloneMarkers.has(marker) || (marker >= 0xd0 && marker <= 0xd7)) {
      offset += 2;
      continue;
    }
    // Start of scan: entropy-coded pixel data follows and there is nothing
    // further worth walking.
    if (marker === 0xda) break;

    const length = view.getUint16(offset + 2);
    if (length < 2 || offset + 2 + length > bytes.length) break;

    const payload = offset + 4;
    const payloadLength = length - 2;

    if (marker >= 0xe0 && marker <= 0xef) {
      appMarkers.push(marker - 0xe0);

      if (marker === 0xe1 && startsWith(bytes, payload, "Exif\0\0")) {
        orientation = readExifOrientation(bytes, payload + 6, payloadLength - 6) ??
          orientation;
      }
      if (marker === 0xe2 && startsWith(bytes, payload, "ICC_PROFILE\0")) {
        iccSegments += 1;
      }
    } else if (frameMarkers.has(marker) && frameHeight === 0) {
      // SOF payload: precision, height, width, component count.
      frameHeight = view.getUint16(payload + 1);
      frameWidth = view.getUint16(payload + 3);
    }

    offset = payload + payloadLength;
  }

  if (frameWidth === 0 || frameHeight === 0) return null;

  const isRotated = orientation >= 5 && orientation <= 8;

  // Any one of these is enough on its own. The endpoint is a black box and
  // the evidence cannot say which of the four it objects to, so a file
  // carrying any of them is rebuilt rather than gambled on. Plain photographs
  // — a bare JFIF header, or a single embedded colour profile — are left
  // exactly as they are, because those have never once been rejected.
  const needsRebuild = orientation !== 1 ||
    iccSegments > 1 ||
    appMarkers.some((n) => n >= 3);

  return {
    frameWidth,
    frameHeight,
    orientation,
    appMarkers,
    iccSegments,
    isRotated,
    needsRebuild,
  };
}

/**
 * The size a photograph presents at, once its EXIF rotation is applied.
 *
 * Orientations 5 to 8 store the pixels turned on their side, so a portrait
 * photograph sits in a landscape frame. Anything reasoning about shape has to
 * use these numbers rather than the frame's own.
 */
export function orientedDimensions(
  frameWidth: number,
  frameHeight: number,
  orientation: number,
): { width: number; height: number } {
  return orientation >= 5 && orientation <= 8
    ? { width: frameHeight, height: frameWidth }
    : { width: frameWidth, height: frameHeight };
}

function startsWith(bytes: Uint8Array, offset: number, prefix: string): boolean {
  if (offset + prefix.length > bytes.length) return false;
  for (let i = 0; i < prefix.length; i += 1) {
    if (bytes[offset + i] !== prefix.charCodeAt(i)) return false;
  }
  return true;
}

/**
 * Pulls tag 0x0112 out of IFD0 of an EXIF block.
 *
 * Returns null rather than throwing on anything malformed. A photograph with
 * an unreadable EXIF header is still a perfectly good photograph, and the
 * caller's fallback — treat it as unrotated — is what a browser does too.
 */
function readExifOrientation(
  bytes: Uint8Array,
  tiffStart: number,
  available: number,
): number | null {
  if (available < 8) return null;

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const byteOrder = view.getUint16(tiffStart);
  const littleEndian = byteOrder === 0x4949;
  if (!littleEndian && byteOrder !== 0x4d4d) return null;
  if (view.getUint16(tiffStart + 2, littleEndian) !== 0x002a) return null;

  const ifdOffset = view.getUint32(tiffStart + 4, littleEndian);
  const ifdStart = tiffStart + ifdOffset;
  if (ifdOffset < 8 || ifdStart + 2 > tiffStart + available) return null;

  const entryCount = view.getUint16(ifdStart, littleEndian);
  for (let i = 0; i < entryCount; i += 1) {
    const entry = ifdStart + 2 + i * 12;
    if (entry + 12 > tiffStart + available) return null;

    if (view.getUint16(entry, littleEndian) === 0x0112) {
      const value = view.getUint16(entry + 8, littleEndian);
      return value >= 1 && value <= 8 ? value : null;
    }
  }

  return null;
}

// gpt-image-2 accepts an arbitrary WIDTHxHEIGHT as long as both sides are
// divisible by 16, the aspect ratio stays within 1:3..3:1, and the result fits
// inside 3840x2160. Asking for a concrete size matters: size="auto" picks a
// small output (a 8000x6000 source came back as 1427x1102), so an edit of a
// large photo loses far more resolution than the model actually requires.
const maxLongSide = 3840;
const maxShortSide = 2160;

// Below this the source is small enough that picking a size buys nothing, and
// scaling to a /16 boundary risks upscaling. Let the model decide instead.
const minLongSide = 512;

function roundDownToMultipleOf16(value: number): number {
  return Math.max(16, Math.floor(value / 16) * 16);
}

/**
 * The output size to ask for, given how the source *displays*.
 *
 * Callers must pass oriented dimensions. Passing a rotated photograph's frame
 * size here asks for a portrait result from a landscape image, which is an
 * instruction to transpose the picture that nobody wrote.
 */
export function computeEditSize(width: unknown, height: unknown): string {
  if (
    typeof width !== "number" ||
    typeof height !== "number" ||
    !Number.isFinite(width) ||
    !Number.isFinite(height) ||
    width <= 0 ||
    height <= 0
  ) {
    return "auto";
  }

  const isLandscape = width >= height;
  const sourceLong = isLandscape ? width : height;
  const sourceShort = isLandscape ? height : width;

  if (sourceLong < minLongSide) return "auto";

  // Outside the supported aspect range there is no faithful size to request,
  // so defer rather than distorting the image.
  if (sourceLong / sourceShort > 3) return "auto";

  // Never scale up — that would invent detail the source does not have.
  const scale = Math.min(
    maxLongSide / sourceLong,
    maxShortSide / sourceShort,
    1,
  );

  const long = Math.min(roundDownToMultipleOf16(sourceLong * scale), maxLongSide);
  const short = Math.min(roundDownToMultipleOf16(sourceShort * scale), maxShortSide);

  return isLandscape ? `${long}x${short}` : `${short}x${long}`;
}

/** Reads "2160x2880" back into numbers. Returns null for "auto". */
export function parseSize(size: string): { width: number; height: number } | null {
  const match = /^(\d+)x(\d+)$/.exec(size);
  if (!match) return null;
  return { width: Number(match[1]), height: Number(match[2]) };
}

/**
 * Rewrites a JPEG with every application segment removed except the JFIF
 * header, leaving the compressed pixel data untouched.
 *
 * This is a copy, not a re-encode. The quantisation tables, Huffman tables and
 * entropy-coded scan are passed through byte for byte, so the photograph loses
 * no quality whatsoever — it loses only the EXIF block, the XMP block, the
 * colour profile and the HDR gain map wrapped around it. That matters here:
 * decoding and re-encoding a 24-megapixel photograph inside an edge function
 * would cost about a hundred megabytes of working memory and a generation of
 * JPEG loss, to solve a problem that lives entirely in the metadata.
 *
 * Dropping the colour profile does mean a Display P3 photograph is then read
 * as sRGB, which shifts saturated colours slightly. That is a real cost, taken
 * deliberately: the alternative is guessing which of the segments the remote
 * decoder objects to, and the evidence cannot say.
 */
export function stripApplicationSegments(bytes: Uint8Array): Uint8Array {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return bytes;

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const keep: Array<{ start: number; end: number }> = [];

  let offset = 2;
  let copyFrom = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) {
      offset += 1;
      continue;
    }

    const marker = bytes[offset + 1];
    if (marker === 0xff) {
      offset += 1;
      continue;
    }
    if (standaloneMarkers.has(marker) || (marker >= 0xd0 && marker <= 0xd7)) {
      offset += 2;
      continue;
    }
    // From the scan onwards everything is pixel data and must be copied whole.
    if (marker === 0xda) break;

    const length = view.getUint16(offset + 2);
    if (length < 2 || offset + 2 + length > bytes.length) break;
    const segmentEnd = offset + 2 + length;

    // APP0 carries the JFIF header, which decoders expect to find first.
    // Everything from APP1 up is the wrapping we are here to remove.
    const isUnwantedApp = marker >= 0xe1 && marker <= 0xef;
    if (isUnwantedApp) {
      if (offset > copyFrom) keep.push({ start: copyFrom, end: offset });
      copyFrom = segmentEnd;
    }

    offset = segmentEnd;
  }
  keep.push({ start: copyFrom, end: bytes.length });

  const size = 2 + keep.reduce((total, run) => total + (run.end - run.start), 0);
  const out = new Uint8Array(size);
  out[0] = 0xff;
  out[1] = 0xd8;

  let cursor = 2;
  for (const run of keep) {
    out.set(bytes.subarray(run.start, run.end), cursor);
    cursor += run.end - run.start;
  }

  return out;
}

/**
 * Inserts a minimal EXIF block carrying nothing but an orientation tag.
 *
 * The edited image comes back the way the stripped source was stored — on its
 * side, for a photograph the camera recorded rotated. Turning it upright by
 * rotating pixels would mean decoding and re-encoding a JPEG that is already
 * as good as it will ever get, and paying a generation of compression loss for
 * a quarter turn. Recording the turn instead costs nothing: this writes the
 * same tag the camera wrote, and every viewer that honoured it on the original
 * honours it here.
 */
export function withOrientation(
  bytes: Uint8Array,
  orientation: number,
): Uint8Array {
  if (orientation === 1 || orientation < 1 || orientation > 8) return bytes;
  if (bytes.length < 2 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return bytes;

  // "Exif\0\0", little-endian TIFF header, one IFD entry, no next IFD.
  const exif = new Uint8Array([
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
    0x49, 0x49, 0x2a, 0x00,
    0x08, 0x00, 0x00, 0x00,
    0x01, 0x00,
    0x12, 0x01, // tag 0x0112, Orientation
    0x03, 0x00, // type SHORT
    0x01, 0x00, 0x00, 0x00, // one value
    orientation & 0xff, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // no further IFD
  ]);

  const segmentLength = exif.length + 2;
  const out = new Uint8Array(bytes.length + 4 + exif.length);

  out[0] = 0xff;
  out[1] = 0xd8;
  out[2] = 0xff;
  out[3] = 0xe1;
  out[4] = (segmentLength >> 8) & 0xff;
  out[5] = segmentLength & 0xff;
  out.set(exif, 6);
  out.set(bytes.subarray(2), 6 + exif.length);

  return out;
}
