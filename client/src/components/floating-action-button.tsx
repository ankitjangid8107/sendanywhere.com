import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";
import FileUpload from "./file-upload";

export default function FloatingActionButton() {
  const [showUpload, setShowUpload] = useState(false);

  const scrollToUpload = () => {
    const uploadSection = document.querySelector('.upload-zone-3d');
    if (uploadSection) {
      uploadSection.scrollIntoView({ behavior: 'smooth' });
    } else {
      setShowUpload(true);
    }
  };

  return (
    <>
      <div className="fixed bottom-8 right-8 z-40">
        <Button
          onClick={scrollToUpload}
          className="w-16 h-16 gradient-bg rounded-full shadow-2xl hover:shadow-3xl text-white floating-element hover:scale-110 transition-all duration-300"
        >
          <Plus className="w-6 h-6" />
        </Button>
      </div>

      {showUpload && (
        <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="w-full max-w-2xl">
            <div className="flex justify-end mb-4">
              <Button
                variant="ghost"
                onClick={() => setShowUpload(false)}
                className="text-white hover:text-gray-300"
              >
                ✕
              </Button>
            </div>
            <FileUpload />
          </div>
        </div>
      )}
    </>
  );
}
