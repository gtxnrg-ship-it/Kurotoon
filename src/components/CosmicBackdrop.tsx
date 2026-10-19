import { useEffect, useRef } from 'react';

type Star = { x: number; y: number; radius: number; alpha: number; phase: number; speed: number; hue: number };
type Cloud = { x: number; y: number; radius: number; hue: number; alpha: number; drift: number };
type Pointer = { x: number; y: number; targetX: number; targetY: number; strength: number; targetStrength: number };

function seededRandom(seed: number) {
  let value = seed >>> 0;
  return () => {
    value += 0x6d2b79f5;
    let t = value;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function makeSeed() {
  try {
    const bytes = new Uint32Array(1);
    crypto.getRandomValues(bytes);
    return bytes[0] || 1;
  } catch {
    return (Date.now() ^ Math.floor(Math.random() * 0xffffffff)) >>> 0;
  }
}

export function CosmicBackdrop() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const context = canvas?.getContext('2d', { alpha: false, desynchronized: true });
    if (!canvas || !context) return;

    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const coarsePointer = window.matchMedia('(pointer: coarse)').matches;
    const random = seededRandom(makeSeed());
    const pointer: Pointer = { x: 0, y: 0, targetX: 0, targetY: 0, strength: 0, targetStrength: 0 };
    let width = 0;
    let height = 0;
    let pixelRatio = 1;
    let frame = 0;
    let lastFrame = 0;
    let elapsed = 0;
    let visible = !document.hidden;
    let disposed = false;

    const starCount = Math.min(230, Math.max(85, Math.round((window.innerWidth * window.innerHeight) / (coarsePointer ? 8500 : 6200))));
    const stars: Star[] = Array.from({ length: starCount }, () => ({
      x: random(), y: random(), radius: 0.25 + random() * (coarsePointer ? 1.0 : 1.35),
      alpha: 0.12 + random() * 0.56, phase: random() * Math.PI * 2,
      speed: 0.12 + random() * 0.42, hue: random() > 0.82 ? 265 + random() * 35 : 190 + random() * 35,
    }));
    const clouds: Cloud[] = Array.from({ length: coarsePointer ? 8 : 12 }, (_, index) => ({
      x: random(), y: random(), radius: 0.14 + random() * 0.28,
      hue: index % 4 === 0 ? 266 + random() * 24 : index % 3 === 0 ? 222 + random() * 24 : 190 + random() * 28,
      alpha: 0.035 + random() * 0.045, drift: (random() - 0.5) * 0.006,
    }));

    const resize = () => {
      width = window.innerWidth;
      height = window.innerHeight;
      pixelRatio = Math.min(window.devicePixelRatio || 1, coarsePointer ? 1.25 : 1.5);
      canvas.width = Math.floor(width * pixelRatio);
      canvas.height = Math.floor(height * pixelRatio);
      canvas.style.width = width + 'px';
      canvas.style.height = height + 'px';
      context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
      paint(0, true);
    };

    const paint = (time: number, still = false) => {
      if (!width || !height) return;
      context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
      context.fillStyle = '#080b16';
      context.fillRect(0, 0, width, height);

      // Broad, overlapping colour fields create a continuous universe rather than a particle wallpaper.
      const baseGlow = context.createRadialGradient(width * 0.72, height * 0.18, 0, width * 0.72, height * 0.18, Math.max(width, height) * 0.86);
      baseGlow.addColorStop(0, 'rgba(24, 45, 91, 0.25)');
      baseGlow.addColorStop(0.38, 'rgba(23, 25, 67, 0.16)');
      baseGlow.addColorStop(1, 'rgba(8, 11, 22, 0)');
      context.fillStyle = baseGlow;
      context.fillRect(0, 0, width, height);

      for (const cloud of clouds) {
        const drift = reducedMotion.matches ? 0 : Math.sin(time * 0.000035 + cloud.x * 8) * cloud.drift;
        const cx = (cloud.x + drift + pointer.x * pointer.strength * 0.018) * width;
        const cy = (cloud.y + Math.cos(time * 0.000025 + cloud.y * 9) * (reducedMotion.matches ? 0 : cloud.drift)) * height;
        const radius = cloud.radius * Math.max(width, height);
        const gradient = context.createRadialGradient(cx, cy, 0, cx, cy, radius);
        gradient.addColorStop(0, `hsla(${cloud.hue}, 78%, 57%, ${cloud.alpha})`);
        gradient.addColorStop(0.42, `hsla(${cloud.hue}, 72%, 42%, ${cloud.alpha * 0.48})`);
        gradient.addColorStop(1, `hsla(${cloud.hue}, 65%, 30%, 0)`);
        context.fillStyle = gradient;
        context.fillRect(Math.max(0, cx - radius), Math.max(0, cy - radius), Math.min(width, radius * 2), Math.min(height, radius * 2));
      }

      // Sparse, very soft filaments suggest large-scale cosmic structure without competing with content.
      context.save();
      context.globalCompositeOperation = 'screen';
      for (let i = 0; i < 4; i++) {
        const shift = reducedMotion.matches ? 0 : Math.sin(time * 0.00004 + i) * 16;
        context.beginPath();
        context.moveTo(width * (-0.08 + i * 0.19), height * (0.13 + i * 0.17));
        context.bezierCurveTo(width * 0.32 + shift, height * (0.05 + i * 0.12), width * 0.55 - shift, height * (0.88 - i * 0.1), width * (0.7 + i * 0.13), height * (0.22 + i * 0.16));
        context.strokeStyle = i % 2 ? 'rgba(70, 126, 220, 0.025)' : 'rgba(91, 105, 220, 0.026)';
        context.lineWidth = 18 + i * 8;
        context.shadowColor = '#5267d8';
        context.shadowBlur = 22;
        context.stroke();
      }
      context.restore();

      for (const star of stars) {
        const twinkle = reducedMotion.matches ? 0 : Math.sin(time * 0.0005 * star.speed + star.phase) * 0.13;
        const parallax = pointer.strength * 0.008;
        const sx = ((star.x + pointer.x * parallax + 1) % 1) * width;
        const sy = ((star.y + pointer.y * parallax + 1) % 1) * height;
        const alpha = Math.max(0.06, Math.min(0.9, star.alpha + twinkle));
        context.beginPath();
        context.arc(sx, sy, star.radius, 0, Math.PI * 2);
        context.fillStyle = `hsla(${star.hue}, 85%, 86%, ${alpha})`;
        context.fill();
        if (star.radius > 1.05 && alpha > 0.52) {
          context.strokeStyle = `rgba(153, 198, 255, ${alpha * 0.18})`;
          context.lineWidth = 0.6;
          context.beginPath();
          context.moveTo(sx - 3.5, sy);
          context.lineTo(sx + 3.5, sy);
          context.moveTo(sx, sy - 3.5);
          context.lineTo(sx, sy + 3.5);
          context.stroke();
        }
      }

      // Touch creates a temporary, restrained space ripple; navigation gestures remain untouched.
      if (pointer.strength > 0.015) {
        const px = pointer.x * width;
        const py = pointer.y * height;
        const radius = 35 + pointer.strength * 145;
        const ripple = context.createRadialGradient(px, py, 0, px, py, radius);
        ripple.addColorStop(0, `rgba(111, 183, 255, ${pointer.strength * 0.035})`);
        ripple.addColorStop(0.7, `rgba(122, 139, 255, ${pointer.strength * 0.018})`);
        ripple.addColorStop(1, 'rgba(122, 139, 255, 0)');
        context.fillStyle = ripple;
        context.fillRect(px - radius, py - radius, radius * 2, radius * 2);
      }
      if (still) return;
    };

    const animate = (time: number) => {
      if (disposed || !visible) return;
      if (reducedMotion.matches) {
        paint(0);
        return;
      }
      frame = window.requestAnimationFrame(animate);
      // Cap the ambient layer at ~30fps to protect battery and leave the main thread for reading.
      if (time - lastFrame < 33) return;
      lastFrame = time;
      elapsed = time;
      pointer.x += (pointer.targetX - pointer.x) * 0.08;
      pointer.y += (pointer.targetY - pointer.y) * 0.08;
      pointer.strength += (pointer.targetStrength - pointer.strength) * 0.075;
      if (pointer.targetStrength > 0) pointer.targetStrength *= 0.985;
      else pointer.targetStrength = Math.max(0, pointer.targetStrength);
      paint(elapsed);
    };

    const wake = () => {
      visible = !document.hidden;
      if (visible && !disposed) {
        lastFrame = 0;
        frame = window.requestAnimationFrame(animate);
      } else {
        window.cancelAnimationFrame(frame);
      }
    };
    const onPointerMove = (event: PointerEvent) => {
      pointer.targetX = event.clientX / Math.max(1, width);
      pointer.targetY = event.clientY / Math.max(1, height);
      pointer.targetStrength = Math.min(1, pointer.targetStrength + (event.pointerType === 'touch' ? 0.5 : 0.12));
    };
    const onPointerDown = (event: PointerEvent) => {
      pointer.targetX = event.clientX / Math.max(1, width);
      pointer.targetY = event.clientY / Math.max(1, height);
      pointer.targetStrength = event.pointerType === 'touch' ? 1 : 0.45;
    };
    const onPointerEnd = () => { pointer.targetStrength = 0; };

    window.addEventListener('resize', resize, { passive: true });
    window.addEventListener('pointermove', onPointerMove, { passive: true });
    window.addEventListener('pointerdown', onPointerDown, { passive: true });
    window.addEventListener('pointerup', onPointerEnd, { passive: true });
    window.addEventListener('pointercancel', onPointerEnd, { passive: true });
    document.addEventListener('visibilitychange', wake);
    const motionChange = () => {
      window.cancelAnimationFrame(frame);
      lastFrame = 0;
      if (reducedMotion.matches) paint(0);
      else if (visible && !disposed) frame = window.requestAnimationFrame(animate);
    };
    reducedMotion.addEventListener?.('change', motionChange);
    resize();
    frame = window.requestAnimationFrame(animate);

    return () => {
      disposed = true;
      window.cancelAnimationFrame(frame);
      window.removeEventListener('resize', resize);
      window.removeEventListener('pointermove', onPointerMove);
      window.removeEventListener('pointerdown', onPointerDown);
      window.removeEventListener('pointerup', onPointerEnd);
      window.removeEventListener('pointercancel', onPointerEnd);
      document.removeEventListener('visibilitychange', wake);
      reducedMotion.removeEventListener?.('change', motionChange);
    };
  }, []);

  return <canvas ref={canvasRef} className="cosmic-backdrop" aria-hidden="true" />;
}
