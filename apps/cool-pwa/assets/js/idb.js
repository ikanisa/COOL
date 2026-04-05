const DB_NAME = 'cool-pwa-db';
const DB_VERSION = 1;

const STORES = {
  settings: { keyPath: 'key' },
  drafts: { keyPath: 'key' },
  queue: { keyPath: 'id' },
  notifications: { keyPath: 'id' },
  shares: { keyPath: 'id' },
  rum: { keyPath: 'id' },
  events: { keyPath: 'id' },
  passkeys: { keyPath: 'id' },
};

let dbPromise;

function openDb() {
  if (dbPromise) {
    return dbPromise;
  }

  dbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = () => {
      const db = request.result;
      for (const [name, options] of Object.entries(STORES)) {
        if (!db.objectStoreNames.contains(name)) {
          db.createObjectStore(name, options);
        }
      }
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });

  return dbPromise;
}

function transact(storeName, mode, handler) {
  return openDb().then((db) => new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, mode);
    const store = tx.objectStore(storeName);
    const request = handler(store);

    if (request) {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    } else {
      tx.oncomplete = () => resolve(undefined);
      tx.onerror = () => reject(tx.error);
    }
  }));
}

export async function dbGet(storeName, key) {
  const result = await transact(storeName, 'readonly', (store) => store.get(key));
  if (!result) {
    return null;
  }
  return Object.prototype.hasOwnProperty.call(result, 'value') ? result.value : result;
}

export function dbSet(storeName, key, value) {
  return transact(storeName, 'readwrite', (store) => store.put({ key, value }));
}

export function dbPutRecord(storeName, record) {
  return transact(storeName, 'readwrite', (store) => store.put(record));
}

export function dbDelete(storeName, key) {
  return transact(storeName, 'readwrite', (store) => store.delete(key));
}

export function dbAdd(storeName, record) {
  return transact(storeName, 'readwrite', (store) => store.add(record));
}

export function dbGetAll(storeName) {
  return transact(storeName, 'readonly', (store) => store.getAll());
}

export function dbCount(storeName) {
  return transact(storeName, 'readonly', (store) => store.count());
}
