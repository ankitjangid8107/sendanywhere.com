import React from "react";
import { useParams } from "wouter";
import { useQuery } from "@tanstack/react-query";
import { Button } from "../components/ui/button";
import { Card, CardContent } from "../components/ui/card";
import { Download as DownloadIcon, FileText, AlertCircle } from "lucide-react";
import { formatFileSize } from "../lib/file-utils";

export default function Download() {
  const { code } = useParams<{ code: string }>();

  const { data: file, isLoading, error } = useQuery({
    queryKey: ['/api/files/code', code],
    enabled: !!code,
  });

  const handleDownload = () => {
    window.open(`/api/download/${code}`, '_blank');
  };

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[var(--light-bg)]">
        <div className="animate-spin rounded-full h-32 w-32 border-b-2 border-[var(--primary)]"></div>
      </div>
    );
  }

  if (error || !file) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[var(--light-bg)]">
        <Card className="w-full max-w-md mx-4">
          <CardContent className="pt-6">
            <div className="flex mb-4 gap-2 items-center justify-center">
              <AlertCircle className="h-8 w-8 text-red-500" />
              <h1 className="text-2xl font-bold text-gray-900">File Not Found</h1>
            </div>
            <p className="mt-4 text-sm text-gray-600 text-center">
              The file you're looking for has expired, been downloaded, or doesn't exist.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-[var(--light-bg)] p-4">
      <Card className="w-full max-w-lg card-3d">
        <CardContent className="pt-8 pb-8">
          <div className="text-center mb-8">
            <div className="w-20 h-20 gradient-bg rounded-full flex items-center justify-center mx-auto mb-4 floating-element">
              <FileText className="h-10 w-10 text-white" />
            </div>
            <h1 className="text-2xl font-bold mb-2">Download Ready</h1>
            <p className="text-gray-600">Your file is ready for download</p>
          </div>

          <div className="bg-[var(--light-bg)] rounded-xl p-6 mb-6">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="font-semibold text-lg mb-1">{file.originalName}</h3>
                <p className="text-gray-600">{formatFileSize(file.size)}</p>
              </div>
              <FileText className="h-8 w-8 text-[var(--primary)]" />
            </div>
          </div>

          <Button 
            onClick={handleDownload}
            className="w-full gradient-bg text-white py-6 text-lg font-semibold shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-300"
          >
            <DownloadIcon className="mr-2 h-5 w-5" />
            Download File
          </Button>

          <div className="mt-6 text-center">
            <p className="text-sm text-gray-500">
              This file will be automatically deleted after download for your security.
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
