import React from "react";
const stats = [
  { value: "2.5M+", label: "Files Shared Daily" },
  { value: "150+", label: "Countries Served" },
  { value: "99.9%", label: "Uptime" },
  { value: "50TB+", label: "Data Transferred" },
];

export default function StatsSection() {
  return (
    <section className="py-20 gradient-bg">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center mb-16">
          <h2 className="text-3xl lg:text-4xl font-bold text-white mb-4">
            Trusted by Millions Worldwide
          </h2>
          <p className="text-xl text-white/80">Join the global community of secure file sharers</p>
        </div>

        <div className="grid md:grid-cols-4 gap-8">
          {stats.map((stat, index) => (
            <div key={stat.label} className="text-center glass-effect rounded-2xl p-8 card-3d">
              <div className="text-4xl lg:text-5xl font-bold text-white mb-2">{stat.value}</div>
              <div className="text-white/80 text-lg">{stat.label}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
