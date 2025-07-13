import { Twitter, Facebook, Linkedin, Github, Apple, Play, Globe } from "lucide-react";

export default function Footer() {
  return (
    <footer className="bg-[var(--text-dark)] text-white py-16">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="grid md:grid-cols-4 gap-8 mb-12">
          <div className="md:col-span-2">
            <h3 className="text-2xl font-bold mb-4 gradient-bg bg-clip-text text-transparent">
              FileFluxTransfer
            </h3>
            <p className="text-gray-400 mb-6 leading-relaxed">
              Created by Ankit Jangid. The most secure and user-friendly file sharing platform. 
              Share files instantly across all your devices with enterprise-grade security.
            </p>
            <div className="flex space-x-4">
              <a href="#" className="w-10 h-10 bg-[var(--primary)] rounded-full flex items-center justify-center hover:bg-[var(--primary)]/80 transition-colors duration-200">
                <Twitter className="w-4 h-4" />
              </a>
              <a href="#" className="w-10 h-10 bg-[var(--primary)] rounded-full flex items-center justify-center hover:bg-[var(--primary)]/80 transition-colors duration-200">
                <Facebook className="w-4 h-4" />
              </a>
              <a href="#" className="w-10 h-10 bg-[var(--primary)] rounded-full flex items-center justify-center hover:bg-[var(--primary)]/80 transition-colors duration-200">
                <Linkedin className="w-4 h-4" />
              </a>
              <a href="#" className="w-10 h-10 bg-[var(--primary)] rounded-full flex items-center justify-center hover:bg-[var(--primary)]/80 transition-colors duration-200">
                <Github className="w-4 h-4" />
              </a>
            </div>
          </div>

          <div>
            <h4 className="text-lg font-semibold mb-4">Product</h4>
            <ul className="space-y-2 text-gray-400">
              <li><a href="#features" className="hover:text-[var(--primary)] transition-colors duration-200">Features</a></li>
              <li><a href="#" className="hover:text-[var(--primary)] transition-colors duration-200">Security</a></li>
              <li><a href="#" className="hover:text-[var(--primary)] transition-colors duration-200">API</a></li>
              <li><a href="#" className="hover:text-[var(--primary)] transition-colors duration-200">Enterprise</a></li>
            </ul>
          </div>

          <div>
            <h4 className="text-lg font-semibold mb-4">Support</h4>
            <ul className="space-y-2 text-gray-400">
              <li><a href="#" className="hover:text-[var(--primary)] transition-colors duration-200">Help Center</a></li>
              <li><a href="#" className="hover:text-[var(--primary)] transition-colors duration-200">Contact Us</a></li>
              <li><a href="#" className="hover:text-[var(--primary)] transition-colors duration-200">Privacy Policy</a></li>
              <li><a href="#" className="hover:text-[var(--primary)] transition-colors duration-200">Terms of Service</a></li>
            </ul>
          </div>
        </div>

        <div className="border-t border-gray-700 pt-8 flex flex-col md:flex-row justify-between items-center">
          <p className="text-gray-400 mb-4 md:mb-0">
            © 2024 FileFluxTransfer by Ankit Jangid. All rights reserved.
          </p>
          <div className="flex items-center space-x-6 text-gray-400">
            <span>Available on:</span>
            <Apple className="w-5 h-5" />
            <Play className="w-5 h-5" />
            <Globe className="w-5 h-5" />
          </div>
        </div>
      </div>
    </footer>
  );
}
