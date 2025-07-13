import React from "react";
import { useState, useCallback } from "react";
import { useDropzone } from "react-dropzone";
import { useMutation } from "@tanstack/react-query";
import { Button } from "./ui/button";
import { Progress } from "./ui/progress";
import { X, Upload, Cloud, Rocket } from "lucide-react";
import { formatFileSize } from "../lib/file-utils";
import { useToast } from "../hooks/use-toast";
import ShareSuccessModal from "./share-success-modal";

interface FileWithPreview {
  id: string;
  file: File;
}

export default function FileUpload() {
  const [files, setFiles] = useState<FileWithPreview[]>([]);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [successData, setSuccessData] = useState<any>(null);
  const { toast } = useToast();

  const uploadMutation = useMutation({
    mutationFn: async (file: File) => {
      console.log('Starting upload for file:', file.name, 'Size:', file.size);
      const formData = new FormData();
      formData.append('file', file);
      console.log('FormData created, file appended');
      const xhr = new XMLHttpRequest();
      return new Promise((resolve, reject) => {
        xhr.upload.addEventListener('progress', (event) => {
          if (event.lengthComputable) {
            const progress = Math.round((event.loaded / event.total) * 100);
            setUploadProgress(progress);
          }
        });
        xhr.addEventListener('load', () => {
          if (xhr.status >= 200 && xhr.status < 300) {
            try {
              const response = JSON.parse(xhr.responseText);
              resolve(response);
            } catch (e) {
              reject(new Error('Invalid JSON response'));
            }
          } else {
            reject(new Error(`HTTP ${xhr.status}: ${xhr.responseText}`));
          }
        });
        xhr.addEventListener('error', () => {
          reject(new Error('Network error'));
        });
        xhr.open('POST', '/api/upload');
        xhr.send(formData);
      });
    },
    onSuccess: (data) => {
      setSuccessData(data);
      setFiles([]);
      setUploadProgress(0);
      toast({
        title: "Upload successful!",
        description: "Your file has been uploaded and is ready to share.",
      });
    },
    onError: (error) => {
      setUploadProgress(0);
      toast({
        title: "Upload failed",
        description: "There was an error uploading your file. Please try again.",
        variant: "destructive",
      });
    },
  });

  const onDrop = useCallback((acceptedFiles: File[]) => {
    const filesWithId = acceptedFiles.map(file => ({
      id: Math.random().toString(36).substr(2, 9),
      file,
    }));
    setFiles(prev => [...prev, ...filesWithId]);
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    multiple: true,
    maxSize: 30 * 1024 * 1024 * 1024, // 30GB
    noClick: false,
    noKeyboard: false,
    onDropRejected: (fileRejections) => {
      fileRejections.forEach((rejection) => {
        toast({
          title: "File rejected",
          description: `${rejection.file.name}: ${rejection.errors.map(e => e.message).join(', ')}`,
          variant: "destructive",
        });
      });
    },
    onDropAccepted: (acceptedFiles) => {
      // Already handled in onDrop
    },
  });

  const removeFile = (id: string) => {
    setFiles(files.filter(file => file.id !== id));
  };

  const handleUpload = () => {
    if (files.length > 0) {
      uploadMutation.mutate(files[0].file); // Upload the original File object
    } else {
      toast({
        title: "No files selected",
        description: "Please select a file to upload first.",
        variant: "destructive",
      });
    }
  };

  return (
    <>
      <div className="card-3d bg-white rounded-2xl shadow-2xl p-8 border border-gray-100">
        <div className="text-center mb-6">
          <h3 className="text-2xl font-bold mb-2">Upload Your Files</h3>
          <p className="text-gray-600">Drag and drop or click to select files</p>
        </div>
        <div
          {...getRootProps()}
          className={`upload-zone-3d border-3 border-dashed rounded-xl p-12 text-center mb-6 cursor-pointer transition-all duration-300 ${
            isDragActive 
              ? 'border-[var(--accent)] bg-[var(--primary)]/5' 
              : 'border-[var(--primary)] hover:border-[var(--accent)] hover:bg-[var(--primary)]/5'
          }`}
        >
          <input {...getInputProps()} />
          <div className="floating-element">
            <Cloud className="w-16 h-16 text-[var(--primary)] mx-auto mb-4" />
          </div>
          <p className="text-lg font-semibold text-[var(--primary)] mb-2">
            {isDragActive ? 'Drop files here' : 'Drop files here'}
          </p>
          <p className="text-gray-500">or click to browse (up to 30GB)</p>
        </div>
        {uploadMutation.isPending && (
          <div className="progress-3d mb-4">
            <Progress value={uploadProgress} className="h-3" />
            <p className="text-sm text-gray-600 mt-2 text-center">
              Uploading... {uploadProgress}%
            </p>
          </div>
        )}
        {files.length > 0 && (
          <div className="space-y-3 mb-6">
            {files.map((item) => (
              <div key={item.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                <div className="flex items-center space-x-3">
                  <Upload className="w-5 h-5 text-[var(--primary)]" />
                  <span className="font-medium">{item.file.name}</span>
                  <span className="text-sm text-gray-500">{formatFileSize(item.file.size)}</span>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => removeFile(item.id)}
                  className="text-red-500 hover:text-red-700"
                >
                  <X className="w-4 h-4" />
                </Button>
              </div>
            ))}
          </div>
        )}
        <Button
          onClick={handleUpload}
          disabled={files.length === 0 || uploadMutation.isPending}
          className="w-full gradient-bg text-white py-4 text-lg font-semibold shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-300"
        >
          <Rocket className="mr-2 h-5 w-5" />
          Share Files
        </Button>
      </div>
      {successData && (
        <ShareSuccessModal
          data={successData}
          onClose={() => setSuccessData(null)}
        />
      )}
    </>
  );
}
