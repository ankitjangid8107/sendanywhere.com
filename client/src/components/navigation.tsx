import React from "react";
import { useState } from "react";
import { Link } from "wouter";
import { Button } from "./ui/button";
import { Menu, X } from "lucide-react";

export default function Navigation() {
  const [isMenuOpen, setIsMenuOpen] = useState(false);

  return (
    <nav className="sticky top-0 z-50 glass-effect">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          <div className="flex items-center">
            <Link href="/" className="flex-shrink-0">
              <h1 className="text-2xl font-bold gradient-bg bg-clip-text text-transparent">
                FileFluxTransfer
              </h1>
            </Link>
          </div>
          
          <div className="hidden md:block">
            <div className="ml-10 flex items-baseline space-x-4">
              <Link
                href="/"
                className="text-[var(--text-dark)] hover:text-[var(--primary)] transition-colors duration-200 px-3 py-2 rounded-md text-sm font-medium"
              >
                Home
              </Link>
              <a
                href="#features"
                className="text-[var(--text-dark)] hover:text-[var(--primary)] transition-colors duration-200 px-3 py-2 rounded-md text-sm font-medium"
              >
                Features
              </a>
              <a
                href="#mobile"
                className="text-[var(--text-dark)] hover:text-[var(--primary)] transition-colors duration-200 px-3 py-2 rounded-md text-sm font-medium"
              >
                Mobile Apps
              </a>
              <a
                href="#support"
                className="text-[var(--text-dark)] hover:text-[var(--primary)] transition-colors duration-200 px-3 py-2 rounded-md text-sm font-medium"
              >
                Support
              </a>
            </div>
          </div>
          
          <div className="md:hidden">
            <Button
              variant="ghost"
              onClick={() => setIsMenuOpen(!isMenuOpen)}
              className="text-[var(--text-dark)] hover:text-[var(--primary)] focus:outline-none transition-colors duration-200"
            >
              {isMenuOpen ? <X className="h-6 w-6" /> : <Menu className="h-6 w-6" />}
            </Button>
          </div>
        </div>
        
        {/* Mobile menu */}
        {isMenuOpen && (
          <div className="md:hidden">
            <div className="px-2 pt-2 pb-3 space-y-1 sm:px-3 bg-white/90 backdrop-blur-sm rounded-b-lg">
              <Link
                href="/"
                className="text-[var(--text-dark)] hover:text-[var(--primary)] block px-3 py-2 rounded-md text-base font-medium"
                onClick={() => setIsMenuOpen(false)}
              >
                Home
              </Link>
              <a
                href="#features"
                className="text-[var(--text-dark)] hover:text-[var(--primary)] block px-3 py-2 rounded-md text-base font-medium"
                onClick={() => setIsMenuOpen(false)}
              >
                Features
              </a>
              <a
                href="#mobile"
                className="text-[var(--text-dark)] hover:text-[var(--primary)] block px-3 py-2 rounded-md text-base font-medium"
                onClick={() => setIsMenuOpen(false)}
              >
                Mobile Apps
              </a>
              <a
                href="#support"
                className="text-[var(--text-dark)] hover:text-[var(--primary)] block px-3 py-2 rounded-md text-base font-medium"
                onClick={() => setIsMenuOpen(false)}
              >
                Support
              </a>
            </div>
          </div>
        )}
      </div>
    </nav>
  );
}
