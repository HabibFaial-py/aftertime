export default function Home() {
  return (
    <main className="flex min-h-screen items-center justify-center px-8 py-20 text-center">
      <div className="flex w-full max-w-md flex-col items-center">
        <div aria-hidden="true" className="mb-8 flex h-[88px] w-[88px] items-center justify-center rounded-full bg-[#f0dfd2]">
          <div className="h-[38px] w-[26px] rotate-30 rounded-full bg-[#a65338]" />
        </div>
        <h1 className="text-5xl font-semibold tracking-tight text-[#332a25] sm:text-6xl">AfterTime</h1>
        <p className="mt-4 text-xl leading-relaxed text-[#794431]">Write today. Reveal tomorrow.</p>
        <div aria-hidden="true" className="my-7 h-0.5 w-8 bg-[#a65338]" />
        <p className="max-w-sm text-base leading-7 text-[#594b42]">A little space for words worth waiting for. Create a time capsule for your future self or someone you care about, and reveal it when the moment is right.</p>
      </div>
    </main>
  );
}
