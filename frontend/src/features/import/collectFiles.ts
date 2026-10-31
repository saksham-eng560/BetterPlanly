/** Gather plan files from a drop or a picker: single files, several files, or whole folders
 * (Safari unzips Notion exports into a folder). Only plan files are kept, so images never upload. */

const PLAN_FILE = /\.(zip|md|markdown|csv|json|ya?ml)$/i;

export interface PickedFile {
  file: File;
  path: string; // relative path inside the dropped folder, or just the file name
}

function readAll(reader: FileSystemDirectoryReader): Promise<FileSystemEntry[]> {
  // readEntries returns at most ~100 entries per call; keep reading until it returns none
  return new Promise((resolve, reject) => {
    const entries: FileSystemEntry[] = [];
    const next = () =>
      reader.readEntries((batch) => {
        if (!batch.length) return resolve(entries);
        entries.push(...batch);
        next();
      }, reject);
    next();
  });
}

async function walk(entry: FileSystemEntry, out: PickedFile[]): Promise<void> {
  if (entry.isFile) {
    if (!PLAN_FILE.test(entry.name) || entry.name.startsWith(".")) return;
    const file = await new Promise<File>((resolve, reject) => (entry as FileSystemFileEntry).file(resolve, reject));
    out.push({ file, path: entry.fullPath.replace(/^\//, "") });
  } else if (entry.isDirectory) {
    for (const child of await readAll((entry as FileSystemDirectoryEntry).createReader())) await walk(child, out);
  }
}

export async function filesFromDrop(data: DataTransfer): Promise<PickedFile[]> {
  const entries = [...data.items].map((item) => item.webkitGetAsEntry?.()).filter((e): e is FileSystemEntry => !!e);
  if (!entries.length) return filesFromList(data.files);
  const out: PickedFile[] = [];
  for (const entry of entries) await walk(entry, out);
  return out;
}

export function filesFromList(list: FileList | null): PickedFile[] {
  return [...(list ?? [])]
    .filter((file) => PLAN_FILE.test(file.name) && !file.name.startsWith("."))
    .map((file) => ({ file, path: file.webkitRelativePath || file.name }));
}
