import { users, files, type User, type InsertUser, type File, type InsertFile } from "@shared/schema";
import * as fs from 'fs';
import * as path from 'path';

export interface IStorage {
  getUser(id: number): Promise<User | undefined>;
  getUserByUsername(username: string): Promise<User | undefined>;
  createUser(user: InsertUser): Promise<User>;
  createFile(file: InsertFile): Promise<File>;
  getFileByCode(code: string): Promise<File | undefined>;
  getFileByLink(link: string): Promise<File | undefined>;
  markFileAsDownloaded(id: number): Promise<void>;
  deleteExpiredFiles(): Promise<void>;
  deleteFile(id: number): Promise<void>;
}

export class MemStorage implements IStorage {
  private users: Map<number, User>;
  private files: Map<number, File>;
  private currentUserId: number;
  private currentFileId: number;
  private uploadsDir: string;

  constructor() {
    this.users = new Map();
    this.files = new Map();
    this.currentUserId = 1;
    this.currentFileId = 1;
    this.uploadsDir = path.join(process.cwd(), 'uploads');
    
    // Ensure uploads directory exists
    if (!fs.existsSync(this.uploadsDir)) {
      fs.mkdirSync(this.uploadsDir, { recursive: true });
    }

    // Clean up expired files every hour
    setInterval(() => {
      this.deleteExpiredFiles();
    }, 60 * 60 * 1000);
  }

  async getUser(id: number): Promise<User | undefined> {
    return this.users.get(id);
  }

  async getUserByUsername(username: string): Promise<User | undefined> {
    return Array.from(this.users.values()).find(
      (user) => user.username === username,
    );
  }

  async createUser(insertUser: InsertUser): Promise<User> {
    const id = this.currentUserId++;
    const user: User = { ...insertUser, id };
    this.users.set(id, user);
    return user;
  }

  async createFile(insertFile: InsertFile): Promise<File> {
    const id = this.currentFileId++;
    const file: File = { 
      ...insertFile, 
      id,
      isDownloaded: false,
      createdAt: new Date()
    };
    this.files.set(id, file);
    return file;
  }

  async getFileByCode(code: string): Promise<File | undefined> {
    return Array.from(this.files.values()).find(
      (file) => file.downloadCode === code && !file.isDownloaded && file.expiresAt > new Date()
    );
  }

  async getFileByLink(link: string): Promise<File | undefined> {
    return Array.from(this.files.values()).find(
      (file) => file.downloadLink === link && !file.isDownloaded && file.expiresAt > new Date()
    );
  }

  async markFileAsDownloaded(id: number): Promise<void> {
    const file = this.files.get(id);
    if (file) {
      file.isDownloaded = true;
      this.files.set(id, file);
    }
  }

  async deleteExpiredFiles(): Promise<void> {
    const now = new Date();
    const expiredFiles = Array.from(this.files.values()).filter(
      (file) => file.expiresAt <= now || file.isDownloaded
    );

    for (const file of expiredFiles) {
      await this.deleteFile(file.id);
    }
  }

  async deleteFile(id: number): Promise<void> {
    const file = this.files.get(id);
    if (file) {
      // Delete physical file
      const filePath = path.join(this.uploadsDir, file.filename);
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
      }
      // Remove from memory
      this.files.delete(id);
    }
  }
}

export const storage = new MemStorage();
