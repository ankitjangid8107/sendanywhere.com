import React from "react";
import { useEffect, useState } from "react";
import { useLocation } from "wouter";
import Navigation from "../components/navigation";
import HeroSection from "../components/hero-section";
import FeaturesSection from "../components/features-section";
import MobileAppsSection from "../components/mobile-apps-section";
import StatsSection from "../components/stats-section";
import Footer from "../components/footer";
import FloatingActionButton from "../components/floating-action-button";
import DownloadCodeInput from "../components/download-code-input";

export default function Home() {
  const [location, setLocation] = useLocation();
  const [showDownloadSection, setShowDownloadSection] = useState(false);

  useEffect(() => {
    const urlParams = new URLSearchParams(window.location.search);
    const downloadCode = urlParams.get('download');
    if (downloadCode) {
      setShowDownloadSection(true);
      setLocation(`/download/${downloadCode}`);
    }
  }, [setLocation]);

  const scrollToDownload = () => {
    setShowDownloadSection(true);
    setTimeout(() => {
      const element = document.getElementById('receive');
      element?.scrollIntoView({ behavior: 'smooth' });
    }, 100);
  };

  return (
    <div className="min-h-screen">
      <Navigation />
      <HeroSection onScrollToReceive={scrollToDownload} />
      {showDownloadSection && (
        <section id="receive" className="py-20 bg-white">
          <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="text-center mb-12">
              <h2 className="text-3xl lg:text-4xl font-bold mb-4">
                Receive Files with{" "}
                <span className="gradient-bg bg-clip-text text-transparent">Download Code</span>
              </h2>
              <p className="text-xl text-gray-600">Enter the 6-digit code to download shared files</p>
            </div>
            <DownloadCodeInput />
          </div>
        </section>
      )}
      <FeaturesSection />
      <MobileAppsSection />
      <StatsSection />
      <Footer />
      <FloatingActionButton />
    </div>
  );
}
