/**
 * Minimal JPEG/EXIF reader for photos picked from the file system or photo
 * library rather than taken live through "Take Photo Here" — those photos
 * already carry their own GPS coordinate and capture time from when they
 * were actually taken, so this reads that back out instead of using the
 * device's current location/time (which would be wrong for a photo taken
 * somewhere else, at some other point). No dependency: hand-parses the
 * JPEG's APP1 segment and the TIFF/IFD structure EXIF uses, reading only
 * the GPS and DateTimeOriginal tags this app actually needs.
 */

export interface PhotoExifInfo {
  location: { lat: number; lng: number } | null;
  capturedAt: number | null;
}

const NO_EXIF: PhotoExifInfo = { location: null, capturedAt: null };

const TYPE_SIZES: Record<number, number> = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8 };

interface IFDEntry {
  type: number;
  count: number;
  valuePos: number;
}

export async function readPhotoExif(file: File): Promise<PhotoExifInfo> {
  try {
    const buffer = await file.arrayBuffer();
    return parseJpegExif(new DataView(buffer));
  } catch {
    return NO_EXIF;
  }
}

function parseJpegExif(view: DataView): PhotoExifInfo {
  if (view.byteLength < 4 || view.getUint16(0) !== 0xffd8) return NO_EXIF;

  let offset = 2;
  while (offset + 4 <= view.byteLength) {
    if (view.getUint8(offset) !== 0xff) break;
    const marker = view.getUint8(offset + 1);

    // SOI/RST markers carry no length field and no payload to skip.
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      offset += 2;
      continue;
    }
    if (marker === 0xd9 || marker === 0xda) break; // EOI / start-of-scan — EXIF always comes before this

    const segmentLength = view.getUint16(offset + 2);
    if (marker === 0xe1 && offset + 4 + 6 <= view.byteLength) {
      const exifTagStart = offset + 4;
      if (
        view.getUint32(exifTagStart) === 0x45786966 && // "Exif"
        view.getUint16(exifTagStart + 4) === 0x0000
      ) {
        return parseTiff(view, exifTagStart + 6);
      }
    }
    offset += 2 + segmentLength;
  }
  return NO_EXIF;
}

function parseTiff(view: DataView, tiffStart: number): PhotoExifInfo {
  if (tiffStart + 8 > view.byteLength) return NO_EXIF;
  const byteOrder = view.getUint16(tiffStart, false);
  if (byteOrder !== 0x4949 && byteOrder !== 0x4d4d) return NO_EXIF;
  const little = byteOrder === 0x4949;

  const ifd0Offset = view.getUint32(tiffStart + 4, little);
  const ifd0 = readIFDEntries(view, tiffStart, ifd0Offset, little);

  let capturedAt: number | null = null;
  const exifSubEntry = ifd0.get(0x8769);
  if (exifSubEntry) {
    const exifSubOffset = view.getUint32(exifSubEntry.valuePos, little);
    const exifIfd = readIFDEntries(view, tiffStart, exifSubOffset, little);
    const dateEntry = exifIfd.get(0x9003) ?? exifIfd.get(0x9004);
    if (dateEntry) capturedAt = parseExifDate(readAscii(view, dateEntry));
  }

  let location: { lat: number; lng: number } | null = null;
  const gpsEntry = ifd0.get(0x8825);
  if (gpsEntry) {
    const gpsOffset = view.getUint32(gpsEntry.valuePos, little);
    const gpsIfd = readIFDEntries(view, tiffStart, gpsOffset, little);
    const latRef = gpsIfd.get(0x0001);
    const lat = gpsIfd.get(0x0002);
    const lngRef = gpsIfd.get(0x0003);
    const lng = gpsIfd.get(0x0004);
    if (latRef && lat && lngRef && lng) {
      const latValue = readRationalDMS(view, lat, little);
      const lngValue = readRationalDMS(view, lng, little);
      if (latValue !== null && lngValue !== null) {
        const latSign = readAscii(view, latRef).startsWith("S") ? -1 : 1;
        const lngSign = readAscii(view, lngRef).startsWith("W") ? -1 : 1;
        location = { lat: latValue * latSign, lng: lngValue * lngSign };
      }
    }
  }

  return { location, capturedAt };
}

function readIFDEntries(
  view: DataView,
  tiffStart: number,
  ifdOffset: number,
  little: boolean,
): Map<number, IFDEntry> {
  const entries = new Map<number, IFDEntry>();
  const ifdPos = tiffStart + ifdOffset;
  if (ifdOffset === 0 || ifdPos + 2 > view.byteLength) return entries;
  const count = view.getUint16(ifdPos, little);
  for (let i = 0; i < count; i++) {
    const entryOffset = ifdPos + 2 + i * 12;
    if (entryOffset + 12 > view.byteLength) break;
    const tag = view.getUint16(entryOffset, little);
    const type = view.getUint16(entryOffset + 2, little);
    const num = view.getUint32(entryOffset + 4, little);
    const typeSize = TYPE_SIZES[type] ?? 1;
    const totalSize = typeSize * num;
    const valuePos = totalSize <= 4 ? entryOffset + 8 : tiffStart + view.getUint32(entryOffset + 8, little);
    entries.set(tag, { type, count: num, valuePos });
  }
  return entries;
}

function readAscii(view: DataView, entry: IFDEntry): string {
  const bytes: number[] = [];
  for (let i = 0; i < entry.count && entry.valuePos + i < view.byteLength; i++) {
    const byte = view.getUint8(entry.valuePos + i);
    if (byte === 0) break;
    bytes.push(byte);
  }
  return String.fromCharCode(...bytes);
}

/** Reads a 3-value (degrees, minutes, seconds) RATIONAL array into decimal degrees. */
function readRationalDMS(view: DataView, entry: IFDEntry, little: boolean): number | null {
  if (entry.count < 3 || entry.valuePos + 24 > view.byteLength) return null;
  let degrees = 0;
  for (let i = 0; i < 3; i++) {
    const numerator = view.getUint32(entry.valuePos + i * 8, little);
    const denominator = view.getUint32(entry.valuePos + i * 8 + 4, little);
    const part = denominator === 0 ? 0 : numerator / denominator;
    degrees += i === 0 ? part : part / Math.pow(60, i);
  }
  return degrees;
}

/** EXIF dates are "YYYY:MM:DD HH:MM:SS" with no timezone — treated as local time. */
function parseExifDate(raw: string): number | null {
  const match = raw.match(/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/);
  if (!match) return null;
  const [, year, month, day, hour, minute, second] = match;
  const date = new Date(
    Number(year),
    Number(month) - 1,
    Number(day),
    Number(hour),
    Number(minute),
    Number(second),
  );
  return Number.isNaN(date.getTime()) ? null : date.getTime();
}
