import { QueryClientProvider } from "@tanstack/react-query";
import { MotionConfig } from "motion/react";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import "./design/tokens.css";
import "./design/base.css";

import { App } from "./app/App";
import { queryClient } from "./app/queryClient";
import { initTransparency } from "./design/transparency";

/** The painting: colour fields, the band, the blurred figure and motion streaks (base.css). */
function Paint() {
  return (
    <div className="bg__paint">
      <i className="bg__streaks" />
      <i className="bg__band" />
      <i className="bg__body" />
      <i className="bg__head" />
    </div>
  );
}

/** The environment behind every glass window. Rendered once, as a sibling before the app and
 *  never inside a transformed, filtered or faded wrapper, so glass always sees it. */
function Backdrop() {
  return (
    <div className="bg" aria-hidden="true">
      <Paint />
      <div className="bg__refract"><Paint /></div>
      <div className="bg__reeds" />
    </div>
  );
}

initTransparency();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Backdrop />
    <QueryClientProvider client={queryClient}>
      <MotionConfig reducedMotion="user">
        <App />
      </MotionConfig>
    </QueryClientProvider>
  </StrictMode>,
);
