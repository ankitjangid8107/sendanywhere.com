import React from "react";
import { Button } from "./ui/button";
import { Upload, Download } from "lucide-react";
import FileUpload from "./file-upload";

interface HeroSectionProps {
  onScrollToReceive: () => void;
}

export default function HeroSection({ onScrollToReceive }: HeroSectionProps) {
  const scrollToUpload = () => {
    const uploadSection = document.querySelector('.upload-zone-3d');
    uploadSection?.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <section className="relative overflow-hidden py-20 lg:py-32">
      {/* Background decoration */}
      <div className="absolute inset-0">
        <div className="absolute top-20 left-10 w-72 h-72 gradient-bg rounded-full opacity-10 blur-3xl floating-element"></div>
        <div className="absolute bottom-20 right-10 w-96 h-96 bg-[var(--accent)] rounded-full opacity-10 blur-3xl floating-element" style={{animationDelay: '1s'}}></div>
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative">
        <div className="lg:grid lg:grid-cols-2 lg:gap-12 items-center">
          {/* Content */}
          <div className="mb-12 lg:mb-0 animate-fade-in">
            <h1 className="text-4xl lg:text-6xl font-bold leading-tight mb-6">
              Share Files
              <span className="gradient-bg bg-clip-text text-transparent block">Instantly & Securely</span>
            </h1>
            <p className="text-xl text-gray-600 mb-8 leading-relaxed">
              Send files up to 30GB to anyone, anywhere. No registration required. 
              Your files are encrypted and automatically deleted after download.
            </p>
            <div className="flex flex-col sm:flex-row gap-4">
              <Button 
                onClick={scrollToUpload}
                className="gradient-bg text-white px-8 py-4 text-lg font-semibold shadow-xl hover:shadow-2xl transform hover:scale-105 transition-all duration-300"
              >
                <Upload className="mr-2 h-5 w-5" />
                Start Sharing
              </Button>
              <Button 
                onClick={onScrollToReceive}
                variant="outline"
                className="border-2 border-[var(--primary)] text-[var(--primary)] px-8 py-4 text-lg font-semibold hover:bg-[var(--primary)] hover:text-white transition-all duration-300"
              >
                <Download className="mr-2 h-5 w-5" />
                Receive Files
              </Button>
            </div>
          </div>

          {/* Main Upload Card */}
          <div className="animate-slide-up">
            <FileUpload />
          </div>
        </div>
      </div>
    </section>
  );
}
