"use client";

import { Renderer } from "@openuidev/react-lang";
import type { ActionEvent } from "@openuidev/react-lang";
import { onyxLibrary } from "@/app/app/message/messageComponents/renderers/openui/library";
import "@openuidev/react-ui/components.css";
import "@openuidev/react-ui/defaults.css";

interface OpenUIRendererProps {
  content: string;
  isStreaming: boolean;
  onAction?: (event: ActionEvent) => void;
}

function OpenUIRenderer({ content, isStreaming, onAction }: OpenUIRendererProps) {
  console.log("[OpenUI] Renderer called:", {
    contentLength: content.length,
    isStreaming,
    first200: content.slice(0, 200),
    libraryComponents: Object.keys(onyxLibrary),
  });

  return (
    <div className="openui-renderer my-2">
      <Renderer
        response={content}
        library={onyxLibrary}
        isStreaming={isStreaming}
        onAction={onAction}
        onParseResult={(result) => {
          console.log("[OpenUI] Parse result:", {
            hasResult: !!result,
            errors: result?.meta?.errors,
            unresolved: result?.meta?.unresolved,
            nodeCount: result?.root ? 1 : 0,
            result,
          });
        }}
      />
    </div>
  );
}

export default OpenUIRenderer;
