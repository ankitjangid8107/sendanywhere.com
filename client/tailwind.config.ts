import { Config } from "tailwindcss";
import baseConfig from "../tailwind.config";
import path from "path";

export default {
  ...baseConfig,
  content: [
    path.resolve(__dirname, "src/**/*.{js,jsx,ts,tsx}"),
    path.resolve(__dirname, "index.html"),
  ],
} satisfies Config; 