import type { Express } from "express";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import { insertFileSchema } from "@shared/schema";
import { ZodError } from "zod";
import multer from "multer";
import path from "path";
import { nanoid } from "nanoid";

// Configure multer for file uploads
const uploadsDir = path.join(process.cwd(), 'uploads');
const upload = multer({
  dest: uploadsDir,
  limits: {
    fileSize: 30 * 1024 * 1024 * 1024, // 30GB limit
  },
  fileFilter: (req, file, cb) => {
    // Accept all file types
    cb(null, true);
  },
});

function generateDownloadCode(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let result = '';
  for (let i = 0; i < 6; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

export async function registerRoutes(app: Express): Promise<Server> {
  // Upload file
  app.post("/api/upload", upload.single('file'), async (req, res) => {
    try {
      console.log('Upload request received:', req.file);
      if (!req.file) {
        console.log('No file in request');
        return res.status(400).json({ message: "No file uploaded" });
      }

      const downloadCode = generateDownloadCode();
      const downloadLink = `${req.protocol}://${req.get('host')}/d/${downloadCode}`;
      const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours

      const fileData = {
        filename: req.file.filename,
        originalName: req.file.originalname,
        mimeType: req.file.mimetype,
        size: req.file.size,
        downloadCode,
        downloadLink,
        expiresAt,
      };

      const validatedFile = insertFileSchema.parse(fileData);
      const file = await storage.createFile(validatedFile);

      res.json({
        id: file.id,
        downloadCode: file.downloadCode,
        downloadLink: file.downloadLink,
        expiresAt: file.expiresAt,
        filename: file.originalName,
        size: file.size,
      });
    } catch (error) {
      if (error instanceof ZodError) {
        return res.status(400).json({ message: "Invalid file data", errors: error.errors });
      }
      console.error("Upload error:", error);
      res.status(500).json({ message: "Internal server error" });
    }
  });

  // Get file by download code
  app.get("/api/files/code/:code", async (req, res) => {
    try {
      const { code } = req.params;
      const file = await storage.getFileByCode(code);

      if (!file) {
        return res.status(404).json({ message: "File not found or expired" });
      }

      res.json({
        id: file.id,
        originalName: file.originalName,
        size: file.size,
        mimeType: file.mimeType,
        downloadLink: file.downloadLink,
      });
    } catch (error) {
      console.error("Get file error:", error);
      res.status(500).json({ message: "Internal server error" });
    }
  });

  // Download file
  app.get("/api/download/:code", async (req, res) => {
    try {
      const { code } = req.params;
      const file = await storage.getFileByCode(code);

      if (!file) {
        return res.status(404).json({ message: "File not found or expired" });
      }

      const filePath = path.join(uploadsDir, file.filename);
      
      // Mark file as downloaded
      await storage.markFileAsDownloaded(file.id);

      res.download(filePath, file.originalName, (err) => {
        if (err) {
          console.error("Download error:", err);
          res.status(500).json({ message: "Error downloading file" });
        }
        // File will be deleted by the cleanup process
      });
    } catch (error) {
      console.error("Download error:", error);
      res.status(500).json({ message: "Internal server error" });
    }
  });

  // Public download page route (for QR codes and direct links)
  app.get("/d/:code", (req, res) => {
    // This will be handled by the frontend router
    res.redirect(`/?download=${req.params.code}`);
  });

  const httpServer = createServer(app);
  return httpServer;
}
