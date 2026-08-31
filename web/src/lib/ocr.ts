import { createWorker } from "tesseract.js";

/**
 * Runs on-device OCR (via tesseract.js, WASM — no server involved) over a
 * screenshot of an Instagram caption, so people can snap a photo of the
 * caption instead of copy-pasting it by hand. Recognizes Korean + English
 * since captions in this app are commonly one or the other.
 */
export async function recognizeCaptionImage(image: File): Promise<string> {
  const worker = await createWorker(["kor", "eng"]);
  try {
    const {
      data: { text },
    } = await worker.recognize(image);
    return text.trim();
  } finally {
    await worker.terminate();
  }
}
