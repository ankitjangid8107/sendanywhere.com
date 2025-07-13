import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Check, Copy, Clock, QrCode } from "lucide-react";
import { useToast } from "@/hooks/use-toast";

interface ShareSuccessModalProps {
  data: {
    downloadCode: string;
    downloadLink: string;
    filename: string;
    expiresAt: string;
  };
  onClose: () => void;
}

export default function ShareSuccessModal({ data, onClose }: ShareSuccessModalProps) {
  const [copied, setCopied] = useState<'code' | 'link' | null>(null);
  const { toast } = useToast();

  const copyToClipboard = async (text: string, type: 'code' | 'link') => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(type);
      setTimeout(() => setCopied(null), 2000);
      toast({
        title: "Copied!",
        description: `${type === 'code' ? 'Download code' : 'Download link'} copied to clipboard.`,
      });
    } catch (err) {
      console.error('Failed to copy:', err);
    }
  };

  const formatExpiryTime = (expiresAt: string) => {
    const expiry = new Date(expiresAt);
    const now = new Date();
    const diffHours = Math.ceil((expiry.getTime() - now.getTime()) / (1000 * 60 * 60));
    return `${diffHours} hours`;
  };

  return (
    <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <Card className="w-full max-w-lg card-3d animate-slide-up">
        <CardContent className="pt-8 pb-8">
          <div className="text-center mb-6">
            <div className="w-16 h-16 bg-[var(--success)] rounded-full flex items-center justify-center mx-auto mb-4">
              <Check className="w-8 h-8 text-white" />
            </div>
            <h3 className="text-2xl font-bold mb-2">Files Shared Successfully!</h3>
            <p className="text-gray-600">Share this code or QR code with the recipient</p>
          </div>

          <div className="bg-[var(--light-bg)] rounded-xl p-6 mb-6 text-center">
            <p className="text-sm text-gray-600 mb-2">Download Code</p>
            <div className="text-4xl font-bold tracking-widest gradient-bg bg-clip-text text-transparent mb-4">
              {data.downloadCode}
            </div>
            <Button
              variant="ghost"
              onClick={() => copyToClipboard(data.downloadCode, 'code')}
              className="text-[var(--primary)] hover:text-[var(--primary)]/80 transition-colors duration-200"
            >
              <Copy className="mr-2 h-4 w-4" />
              {copied === 'code' ? 'Copied!' : 'Copy Code'}
            </Button>
          </div>

          <div className="text-center mb-6">
            <div className="w-32 h-32 bg-gray-200 rounded-xl mx-auto mb-4 flex items-center justify-center">
              <QrCode className="w-16 h-16 text-gray-400" />
            </div>
            <p className="text-sm text-gray-600">Scan to download on mobile</p>
          </div>

          <div className="flex gap-3 mb-6">
            <input
              type="text"
              value={data.downloadLink}
              readOnly
              className="flex-1 px-4 py-3 bg-[var(--light-bg)] rounded-xl text-sm border border-gray-200 focus:outline-none"
            />
            <Button
              onClick={() => copyToClipboard(data.downloadLink, 'link')}
              className="px-4 py-3 bg-[var(--primary)] text-white rounded-xl hover:bg-[var(--primary)]/90 transition-colors duration-200"
            >
              <Copy className="w-4 h-4" />
            </Button>
          </div>

          <div className="bg-yellow-50 border border-yellow-200 rounded-xl p-4 mb-6">
            <div className="flex items-center">
              <Clock className="w-5 h-5 text-yellow-600 mr-3" />
              <div>
                <p className="text-sm font-medium text-yellow-800">
                  Auto-Delete in {formatExpiryTime(data.expiresAt)}
                </p>
                <p className="text-xs text-yellow-600">
                  Files will be permanently deleted after first download or 24 hours
                </p>
              </div>
            </div>
          </div>

          <div className="flex gap-3">
            <Button
              variant="outline"
              onClick={() => {
                onClose();
                // Reset form for another upload
              }}
              className="flex-1"
            >
              Share Another
            </Button>
            <Button
              onClick={onClose}
              className="flex-1 gradient-bg text-white shadow-lg hover:shadow-xl transition-all duration-300"
            >
              Done
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
