'use strict';
// Small database layer.
//   - If MONGODB_URI is set  -> data is saved in MongoDB (permanent, recommended for Render).
//   - Otherwise              -> data is saved in a JSON file (data/db.json). On Render FREE plan this
//                               file is erased on every restart, so use MongoDB there.
// All records are also kept in memory, so searching and reading is very fast.
const fs = require('fs');
const path = require('path');

const COLLECTIONS = ['places', 'posts', 'ambulances', 'trips', 'meta'];

// ---------- backend 1: JSON file ----------
class FileBackend {
  constructor(file) {
    this.kind = 'file';
    this.file = file;
    this.cache = {};
    this.timer = null;
  }
  async load() {
    COLLECTIONS.forEach((c) => (this.cache[c] = {}));
    try {
      const raw = fs.readFileSync(this.file, 'utf8');
      const obj = JSON.parse(raw);
      for (const c of COLLECTIONS) if (obj[c] && typeof obj[c] === 'object') this.cache[c] = obj[c];
    } catch (e) {
      if (e.code !== 'ENOENT') console.warn('db file could not be read, starting empty:', e.message);
    }
    const out = {};
    for (const c of COLLECTIONS) out[c] = Object.values(this.cache[c]);
    return out;
  }
  _schedule() {
    if (this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      this.flush();
    }, 300);
    if (this.timer.unref) this.timer.unref();
  }
  flush() {
    try {
      fs.mkdirSync(path.dirname(this.file), { recursive: true });
      const tmp = this.file + '.tmp';
      fs.writeFileSync(tmp, JSON.stringify(this.cache));
      fs.renameSync(tmp, this.file);
    } catch (e) {
      console.warn('db file could not be saved:', e.message);
    }
  }
  async upsert(col, doc) {
    this.cache[col][doc.id] = doc;
    this._schedule();
  }
  async remove(col, id) {
    delete this.cache[col][id];
    this._schedule();
  }
}

// ---------- backend 2: MongoDB ----------
class MongoBackend {
  constructor(uri, dbName) {
    this.kind = 'mongodb';
    this.uri = uri;
    this.dbName = dbName;
  }
  async load() {
    const { MongoClient } = require('mongodb'); // installed by "npm install"
    this.client = new MongoClient(this.uri, { serverSelectionTimeoutMS: 8000 });
    await this.client.connect();
    this.db = this.client.db(this.dbName);
    const out = {};
    for (const c of COLLECTIONS) {
      const rows = await this.db.collection(c).find({}).toArray();
      out[c] = rows.map(({ _id, ...rest }) => ({ id: String(_id), ...rest })); // eslint-disable-line no-unused-vars
    }
    return out;
  }
  async upsert(col, doc) {
    const { id, ...rest } = doc;
    await this.db.collection(col).replaceOne({ _id: id }, rest, { upsert: true });
  }
  async remove(col, id) {
    await this.db.collection(col).deleteOne({ _id: id });
  }
}

class Store {
  constructor() {
    this.data = {};
    COLLECTIONS.forEach((c) => (this.data[c] = new Map()));
    this.backend = null;
    this.kind = 'none';
    this.warning = '';
  }

  async init(opts = {}) {
    const uri = opts.mongoUri !== undefined ? opts.mongoUri : process.env.MONGODB_URI || '';
    const file = opts.file || process.env.DATA_FILE || path.join(__dirname, 'data', 'db.json');
    let backend = null;
    let loaded = null;
    if (uri) {
      try {
        backend = new MongoBackend(uri, process.env.MONGODB_DB || 'amburoute');
        loaded = await backend.load();
      } catch (e) {
        console.error('MongoDB connection FAILED, using the local file instead:', e.message);
        this.warning = 'MongoDB connection failed. Data is NOT permanent right now.';
        backend = null;
        loaded = null;
      }
    }
    if (!backend) {
      backend = new FileBackend(file);
      loaded = await backend.load();
      if (!uri) this.warning = 'MONGODB_URI is not set. Data is saved in a local file and can be lost when Render restarts.';
    }
    this.backend = backend;
    this.kind = backend.kind;
    for (const c of COLLECTIONS) for (const d of loaded[c] || []) this.data[c].set(d.id, d);
    return this;
  }

  list(col) {
    return [...this.data[col].values()];
  }
  get(col, id) {
    return this.data[col].get(id) || null;
  }
  count(col) {
    return this.data[col].size;
  }
  // Saves in memory first (instant), then in the database. A database error never crashes the server.
  put(col, doc) {
    this.data[col].set(doc.id, doc);
    this.backend.upsert(col, doc).catch((e) => console.warn('db save failed:', col, e.message));
    return doc;
  }
  remove(col, id) {
    const had = this.data[col].delete(id);
    this.backend.remove(col, id).catch((e) => console.warn('db delete failed:', col, e.message));
    return had;
  }
  flush() {
    if (this.backend && this.backend.flush) this.backend.flush();
  }
}

module.exports = { Store, COLLECTIONS };
