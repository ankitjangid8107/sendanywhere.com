import { useState } from "react";
import { useLocation } from "wouter";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Key, Link as LinkIcon } from "lucide-react";

export default function DownloadCodeInput() {
  const [code, setCode] = useState(["", "", "", "", "", ""]);
  const [link, setLink] = useState("");
  const [, setLocation] = useLocation();

  const handleCodeChange = (index: number, value: string) => {
    if (value.length > 1) return;
    
    const newCode = [...code];
    newCode[index] = value.toUpperCase();
    setCode(newCode);

    // Auto-advance to next input
    if (value && index < 5) {
      const nextInput = document.querySelector(`input[data-index="${index + 1}"]`) as HTMLInputElement;
      nextInput?.focus();
    }
  };

  const handleKeyDown = (index: number, e: React.KeyboardEvent) => {
    if (e.key === 'Backspace' && !code[index] && index > 0) {
      const prevInput = document.querySelector(`input[data-index="${index - 1}"]`) as HTMLInputElement;
      prevInput?.focus();
    }
  };

  const handleGetFiles = () => {
    const downloadCode = code.join('');
    if (downloadCode.length === 6) {
      setLocation(`/download/${downloadCode}`);
    }
  };

  const handleDownloadFromLink = () => {
    if (link) {
      const match = link.match(/\/d\/([A-Z0-9]{6})/);
      if (match) {
        setLocation(`/download/${match[1]}`);
      } else {
        // Try to extract code from the end of the URL
        const parts = link.split('/');
        const lastPart = parts[parts.length - 1];
        if (lastPart.length === 6) {
          setLocation(`/download/${lastPart}`);
        }
      }
    }
  };

  return (
    <div className="card-3d bg-[var(--light-bg)] rounded-2xl shadow-xl p-8 max-w-2xl mx-auto">
      <div className="text-center mb-8">
        <div className="w-20 h-20 gradient-bg rounded-full flex items-center justify-center mx-auto mb-4 floating-element">
          <Key className="w-8 h-8 text-white" />
        </div>
        <h3 className="text-2xl font-bold mb-2">Enter Download Code</h3>
        <p className="text-gray-600">6-digit code provided by sender</p>
      </div>

      <div className="flex justify-center space-x-3 mb-8">
        {code.map((digit, index) => (
          <Input
            key={index}
            data-index={index}
            type="text"
            maxLength={1}
            value={digit}
            onChange={(e) => handleCodeChange(index, e.target.value)}
            onKeyDown={(e) => handleKeyDown(index, e)}
            className="w-14 h-14 text-center text-2xl font-bold border-2 focus:border-[var(--primary)] transition-colors duration-200"
          />
        ))}
      </div>

      <Button
        onClick={handleGetFiles}
        disabled={code.some(digit => !digit)}
        className="w-full gradient-bg text-white py-4 text-lg font-semibold shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-300 mb-8"
      >
        Get Files
      </Button>

      <div className="text-center">
        <p className="text-gray-500 mb-4">Or paste the full download link</p>
        <div className="flex gap-3">
          <Input
            type="url"
            placeholder="https://fileshare.pro/d/..."
            value={link}
            onChange={(e) => setLink(e.target.value)}
            className="flex-1 focus:border-[var(--primary)] transition-colors duration-200"
          />
          <Button
            onClick={handleDownloadFromLink}
            disabled={!link}
            className="px-6 bg-[var(--accent)] text-white hover:bg-[var(--accent)]/90 transition-colors duration-200"
          >
            <LinkIcon className="w-4 h-4" />
          </Button>
        </div>
      </div>
    </div>
  );
}
