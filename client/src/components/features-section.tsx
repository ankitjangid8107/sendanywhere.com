import React from "react";
import { Shield, Smartphone, Rocket, Infinity, UserX, Clock } from "lucide-react";

const features = [
  {
    icon: Shield,
    title: "End-to-End Encryption",
    description: "Your files are encrypted before upload and automatically deleted after download for maximum security.",
  },
  {
    icon: Smartphone,
    title: "Cross-Platform",
    description: "Share between any devices - web, mobile, desktop. iOS and Android apps available.",
  },
  {
    icon: Rocket,
    title: "Lightning Fast",
    description: "Optimized upload and download speeds with global CDN distribution.",
  },
  {
    icon: Infinity,
    title: "No Size Limits",
    description: "Share files of any size - from documents to large video files and datasets.",
  },
  {
    icon: UserX,
    title: "No Registration",
    description: "Start sharing immediately. No accounts, no logins, no personal information required.",
  },
  {
    icon: Clock,
    title: "Auto-Delete",
    description: "Files automatically deleted after download or 24 hours for privacy protection.",
  },
];

export default function FeaturesSection() {
  return (
    <section id="features" className="py-20 bg-[var(--light-bg)]">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center mb-16">
          <h2 className="text-3xl lg:text-4xl font-bold mb-4">
            Why Choose{" "}
            <span className="gradient-bg bg-clip-text text-transparent">FileFluxTransfer?</span>
          </h2>
          <p className="text-xl text-gray-600 max-w-3xl mx-auto">
            Professional-grade file sharing with enterprise security and consumer simplicity
          </p>
        </div>

        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
          {features.map((feature, index) => (
            <div 
              key={feature.title}
              className="card-3d bg-white rounded-2xl p-8 shadow-lg hover:shadow-xl transition-all duration-300"
            >
              <div 
                className="w-16 h-16 gradient-bg rounded-2xl flex items-center justify-center mb-6 floating-element"
                style={{ animationDelay: `${index * 0.2}s` }}
              >
                <feature.icon className="w-8 h-8 text-white" />
              </div>
              <h3 className="text-xl font-bold mb-4">{feature.title}</h3>
              <p className="text-gray-600 leading-relaxed">{feature.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
