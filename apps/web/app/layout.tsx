import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "AfterTime",
  description: "A little space for words worth waiting for.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
