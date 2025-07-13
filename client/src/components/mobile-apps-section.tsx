import { Button } from "@/components/ui/button";
import { Check, Apple, Play } from "lucide-react";

const features = [
  "Share files directly from your camera roll",
  "Scan QR codes to receive files instantly",
  "Background uploads and downloads",
  "Native share integration",
];

export default function MobileAppsSection() {
  return (
    <section id="mobile" className="py-20 bg-white">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="lg:grid lg:grid-cols-2 lg:gap-16 items-center">
          {/* Content */}
          <div className="mb-12 lg:mb-0">
            <h2 className="text-3xl lg:text-4xl font-bold mb-6">
              Take FileShare Pro{" "}
              <span className="gradient-bg bg-clip-text text-transparent">On The Go</span>
            </h2>
            <p className="text-xl text-gray-600 mb-8 leading-relaxed">
              Download our mobile apps for seamless file sharing between your phone, tablet, and computer. 
              Same security, same speed, optimized for mobile.
            </p>

            {/* App Features */}
            <div className="space-y-4 mb-8">
              {features.map((feature, index) => (
                <div key={index} className="flex items-center">
                  <div className="w-8 h-8 bg-[var(--success)] rounded-full flex items-center justify-center mr-4">
                    <Check className="w-4 h-4 text-white" />
                  </div>
                  <span className="text-lg">{feature}</span>
                </div>
              ))}
            </div>

            {/* Download Buttons */}
            <div className="flex flex-col sm:flex-row gap-4">
              <Button className="inline-flex items-center justify-center bg-black text-white px-6 py-4 hover:bg-gray-800 transition-colors duration-200">
                <Apple className="mr-4 w-6 h-6" />
                <div className="text-left">
                  <div className="text-xs">Download on the</div>
                  <div className="text-lg font-semibold">App Store</div>
                </div>
              </Button>
              <Button className="inline-flex items-center justify-center bg-black text-white px-6 py-4 hover:bg-gray-800 transition-colors duration-200">
                <Play className="mr-4 w-6 h-6" />
                <div className="text-left">
                  <div className="text-xs">Get it on</div>
                  <div className="text-lg font-semibold">Google Play</div>
                </div>
              </Button>
            </div>
          </div>

          {/* Phone Mockups */}
          <div className="relative">
            <div className="flex justify-center space-x-8">
              {/* Phone 1 */}
              <div className="card-3d transform rotate-12">
                <div className="w-48 h-96 bg-gradient-to-br from-gray-900 to-gray-700 rounded-3xl shadow-2xl p-2">
                  <div className="w-full h-full bg-gradient-to-br from-[var(--primary)] to-[var(--secondary)] rounded-2xl flex items-center justify-center">
                    <div className="text-white text-center">
                      <div className="w-16 h-16 bg-white/20 rounded-2xl mx-auto mb-4 flex items-center justify-center">
                        <Apple className="w-8 h-8" />
                      </div>
                      <p className="text-sm font-medium">FileShare Pro</p>
                      <p className="text-xs opacity-80">iOS App</p>
                    </div>
                  </div>
                </div>
              </div>
              {/* Phone 2 */}
              <div className="card-3d transform -rotate-12">
                <div className="w-48 h-96 bg-gradient-to-br from-gray-900 to-gray-700 rounded-3xl shadow-2xl p-2">
                  <div className="w-full h-full bg-gradient-to-br from-[var(--accent)] to-[var(--primary)] rounded-2xl flex items-center justify-center">
                    <div className="text-white text-center">
                      <div className="w-16 h-16 bg-white/20 rounded-2xl mx-auto mb-4 flex items-center justify-center">
                        <Play className="w-8 h-8" />
                      </div>
                      <p className="text-sm font-medium">FileShare Pro</p>
                      <p className="text-xs opacity-80">Android App</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            
            {/* Floating Elements */}
            <div className="absolute top-10 left-10 w-20 h-20 bg-[var(--primary)]/20 rounded-full blur-xl floating-element"></div>
            <div className="absolute bottom-10 right-10 w-16 h-16 bg-[var(--accent)]/20 rounded-full blur-xl floating-element" style={{animationDelay: '1.5s'}}></div>
          </div>
        </div>
      </div>
    </section>
  );
}
