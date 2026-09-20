#!/usr/bin/env python3
import os
import base64

# Read base64 assets if available
qr_b64 = ""
logo_b64 = ""

if os.path.exists('my_qr_code.png'):
    with open('my_qr_code.png', 'rb') as f:
        qr_b64 = f"data:image/png;base64,{base64.b64encode(f.read()).decode('utf-8')}"

if os.path.exists('logo/Enything_modern.png'):
    with open('logo/Enything_modern.png', 'rb') as f:
        logo_b64 = f"data:image/png;base64,{base64.b64encode(f.read()).decode('utf-8')}"

html_content = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Enything — 2:3 Master Promo Card (enything.in)</title>
    
    <!-- Local & CDN Outfit Fonts for 1000x Razor-Sharp Vector Quality -->
    <style>
        @font-face {{
            font-family: 'Outfit';
            font-weight: 400;
            src: url('assets/google_fonts/Outfit-Regular.ttf') format('truetype');
        }}
        @font-face {{
            font-family: 'Outfit';
            font-weight: 600;
            src: url('assets/google_fonts/Outfit-SemiBold.ttf') format('truetype');
        }}
        @font-face {{
            font-family: 'Outfit';
            font-weight: 700;
            src: url('assets/google_fonts/Outfit-Bold.ttf') format('truetype');
        }}
        @font-face {{
            font-family: 'Outfit';
            font-weight: 800;
            src: url('assets/google_fonts/Outfit-ExtraBold.ttf') format('truetype');
        }}
        @font-face {{
            font-family: 'Outfit';
            font-weight: 900;
            src: url('assets/google_fonts/Outfit-Black.ttf') format('truetype');
        }}
    </style>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@500;700;800&display=swap" rel="stylesheet">
    
    <style>
        /* ==========================================================================
           PRINT ENGINE SPECIFICATION (4x6 Inches // 2:3 Ratio // 300 DPI Ready)
           ========================================================================== */
        @page {{
            size: 4in 6in;
            margin: 0;
        }}

        :root {{
            /* Core Brand Colors from app_colors.dart */
            --primary: #1E3FD8;
            --primary-dark: #070F50;
            --primary-deep: #0F1E80;
            --primary-light: #3D6BFF;
            --secondary: #FF6B35;
            --secondary-light: #FF8C42;
            --accent-gold: #FFCF40;
            --accent-gold-dark: #D4A017;
            
            /* Ecosystem Theme Colors */
            --customer-gradient: linear-gradient(135deg, #0F1E80 0%, #1E3FD8 50%, #3D6BFF 100%);
            --customer-color: #1E3FD8;
            --customer-tint: #EEF3FF;
            
            --seller-gradient: linear-gradient(135deg, #4A148C 0%, #6A1B9A 50%, #AB47BC 100%);
            --seller-color: #6A1B9A;
            --seller-tint: #F8EDFB;
            
            --rider-gradient: linear-gradient(135deg, #004D40 0%, #00695C 50%, #26A69A 100%);
            --rider-color: #00695C;
            --rider-tint: #E6F7F5;
            
            /* Neutral Surfaces */
            --surface-light: #F8F9FE;
            --surface-white: #FFFFFF;
            --dark-bg: #070913;
            --dark-card: #0D1122;
            --text-main: #0B1220;
            --text-muted: #4B5565;
            --text-subtle: #717D96;
            --border-subtle: rgba(15, 30, 128, 0.08);
            --border-card: #DFE4F2;
            
            /* Dimensions: Exactly 4in x 6in (2:3 Aspect Ratio) */
            --card-width: 4in;
            --card-height: 6in;
        }}

        * {{
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
        }}

        body {{
            font-family: 'Outfit', -apple-system, BlinkMacSystemFont, sans-serif;
            background: #060813;
            color: var(--text-main);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 30px 20px 60px;
        }}

        /* ==========================================================================
           STUDIO CONTROLS (Web Screen Preview Only)
           ========================================================================== */
        .studio-header {{
            text-align: center;
            margin-bottom: 25px;
            color: #FFFFFF;
        }}

        .studio-header h1 {{
            font-size: 26px;
            font-weight: 900;
            letter-spacing: -0.03em;
            background: linear-gradient(135deg, #FFFFFF 30%, #A5B4FC 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 6px;
        }}

        .studio-header p {{
            font-size: 14px;
            color: #94A3B8;
            font-weight: 500;
        }}

        .badge-pill {{
            display: inline-flex;
            align-items: center;
            gap: 6px;
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid rgba(255, 255, 255, 0.15);
            padding: 5px 14px;
            border-radius: 100px;
            font-size: 11px;
            font-family: 'JetBrains Mono', monospace;
            color: #A5B4FC;
            margin-top: 10px;
        }}

        .badge-pill span.dot {{
            width: 7px;
            height: 7px;
            border-radius: 50%;
            background: #00C853;
            box-shadow: 0 0 10px #00C853;
        }}

        .preview-controls {{
            display: flex;
            gap: 12px;
            margin-bottom: 30px;
            background: rgba(255, 255, 255, 0.05);
            padding: 6px;
            border-radius: 14px;
            border: 1px solid rgba(255, 255, 255, 0.1);
        }}

        .btn {{
            font-family: 'Outfit', sans-serif;
            font-size: 13px;
            font-weight: 700;
            padding: 10px 20px;
            border-radius: 10px;
            border: none;
            cursor: pointer;
            transition: all 0.2s ease;
            display: flex;
            align-items: center;
            gap: 8px;
        }}

        .btn-primary {{
            background: linear-gradient(135deg, #FF6B35, #FF8C42);
            color: #FFFFFF;
            box-shadow: 0 4px 16px rgba(255, 107, 53, 0.35);
        }}

        .btn-primary:hover {{
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(255, 107, 53, 0.45);
        }}

        .btn-secondary {{
            background: rgba(255, 255, 255, 0.08);
            color: #E2E8F0;
            border: 1px solid rgba(255, 255, 255, 0.12);
        }}

        .btn-secondary:hover {{
            background: rgba(255, 255, 255, 0.14);
            color: #FFFFFF;
        }}

        .btn-secondary.active {{
            background: #1E3FD8;
            color: #FFFFFF;
            border-color: #3D6BFF;
        }}

        /* ==========================================================================
           STAGE CONTAINER (SIDE-BY-SIDE OR 3D INTERACTIVE)
           ========================================================================== */
        .stage-container {{
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 40px;
            perspective: 1400px;
            transition: all 0.4s ease;
        }}

        /* 3D Flip Mode Styles */
        .stage-container.mode-flip {{
            gap: 0;
        }}

        .stage-container.mode-flip .flip-card-3d {{
            width: var(--card-width);
            height: var(--card-height);
            position: relative;
            transform-style: preserve-3d;
            transition: transform 0.8s cubic-bezier(0.175, 0.885, 0.32, 1.275);
            cursor: pointer;
        }}

        .stage-container.mode-flip .flip-card-3d.flipped {{
            transform: rotateY(180deg);
        }}

        .stage-container.mode-flip .card-wrapper {{
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            backface-visibility: hidden;
            -webkit-backface-visibility: hidden;
            margin: 0;
        }}

        .stage-container.mode-flip .card-wrapper.back-side-wrap {{
            transform: rotateY(180deg);
        }}

        .flip-instruction-tag {{
            display: none;
            margin-top: 15px;
            font-size: 13px;
            font-family: 'JetBrains Mono', monospace;
            color: #FF8C42;
            font-weight: 700;
            letter-spacing: 0.05em;
            text-transform: uppercase;
        }}

        .stage-container.mode-flip + .flip-instruction-tag {{
            display: block;
        }}

        /* ==========================================================================
           PHYSICAL CARD CONTAINER (4in x 6in EXACT)
           ========================================================================== */
        .card-wrapper {{
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 12px;
        }}

        .card-label {{
            font-size: 12px;
            font-weight: 800;
            letter-spacing: 0.12em;
            text-transform: uppercase;
            color: #94A3B8;
            font-family: 'JetBrains Mono', monospace;
        }}

        .card-canvas {{
            width: var(--card-width);
            height: var(--card-height);
            position: relative;
            border-radius: 0.18in;
            overflow: hidden;
            box-shadow: 0 25px 60px -10px rgba(0, 0, 0, 0.75), 0 0 0 1px rgba(255, 255, 255, 0.12);
            background-color: var(--surface-white);
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
            display: flex;
            flex-direction: column;
            transition: transform 0.4s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.4s ease;
        }}

        .card-canvas:hover {{
            transform: translateY(-5px);
            box-shadow: 0 35px 80px -15px rgba(30, 63, 216, 0.4), 0 0 0 1px rgba(255, 255, 255, 0.25);
        }}

        /* ==========================================================================
           SIDE A: THE FRONT (MAXIMUM LEGIBILITY & BRAND IDENTITY)
           ========================================================================== */
        .card-front {{
            background: linear-gradient(175deg, #050B3B 0%, #0A1768 28%, #1E3FD8 70%, #2F58FF 100%);
            color: #FFFFFF;
            padding: 0.24in 0.25in 0.22in;
            position: relative;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
        }}

        .bg-mesh-grid {{
            position: absolute;
            inset: 0;
            background-image: radial-gradient(rgba(255, 255, 255, 0.15) 1px, transparent 1px);
            background-size: 0.18in 0.18in;
            opacity: 0.4;
            pointer-events: none;
        }}

        /* Front Header Bar */
        .front-meta-bar {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            z-index: 2;
            border-bottom: 1.5px solid rgba(255, 255, 255, 0.22);
            padding-bottom: 0.08in;
        }}

        .chip-emblem {{
            display: flex;
            align-items: center;
            gap: 0.08in;
        }}

        .sim-chip {{
            width: 0.34in;
            height: 0.25in;
            background: linear-gradient(135deg, #FFD700 0%, #FFA000 50%, #B8860B 100%);
            border-radius: 0.04in;
            border: 1px solid rgba(255, 255, 255, 0.9);
            position: relative;
            display: flex;
            align-items: center;
            justify-content: center;
        }}

        .sim-chip::after {{
            content: '';
            width: 0.2in;
            height: 0.14in;
            border: 0.8px solid rgba(0, 0, 0, 0.4);
            border-radius: 0.02in;
        }}

        .nfc-icon {{
            width: 0.22in;
            height: 0.22in;
            opacity: 0.95;
            fill: #FFFFFF;
        }}

        .pass-badge {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.095in;
            font-weight: 700;
            letter-spacing: 0.06em;
            color: #FFFFFF;
            background: rgba(255, 255, 255, 0.14);
            border: 1.2px solid rgba(255, 255, 255, 0.3);
            padding: 0.04in 0.1in;
            border-radius: 0.05in;
            text-transform: uppercase;
        }}

        /* Hero Brand Presentation */
        .front-hero {{
            display: flex;
            flex-direction: column;
            align-items: center;
            text-align: center;
            z-index: 2;
            margin-top: 0.06in;
        }}

        .app-emblem-container {{
            width: 1.18in;
            height: 1.18in;
            position: relative;
            margin-bottom: 0.08in;
        }}

        .emblem-img {{
            width: 100%;
            height: 100%;
            object-fit: contain;
            position: relative;
            z-index: 1;
        }}

        .brand-title {{
            font-size: 0.54in;
            font-weight: 900;
            letter-spacing: -0.03em;
            line-height: 1;
            margin: 0;
            color: #FFFFFF;
        }}

        .brand-pill {{
            margin-top: 0.08in;
            display: inline-flex;
            align-items: center;
            gap: 0.04in;
            background: rgba(255, 255, 255, 0.18);
            border: 1.5px solid rgba(255, 255, 255, 0.4);
            padding: 0.05in 0.16in;
            border-radius: 100px;
        }}

        .brand-pill-text {{
            font-size: 0.105in;
            font-weight: 800;
            letter-spacing: 0.08em;
            color: #FFFFFF;
            text-transform: uppercase;
        }}

        .tagline-hero {{
            margin-top: 0.1in;
            font-size: 0.21in;
            font-weight: 900;
            letter-spacing: -0.01em;
            line-height: 1.25;
            color: #FFFFFF;
        }}

        .tagline-hero span.accent {{
            color: #FF8C42;
        }}

        /* The 3-Node Harmonic Orbit */
        .triad-nexus {{
            z-index: 2;
            width: 100%;
            background: rgba(7, 15, 80, 0.85);
            border: 1.5px solid rgba(255, 255, 255, 0.25);
            border-radius: 0.14in;
            padding: 0.11in 0.12in;
            margin-top: 0.06in;
            margin-bottom: 0.06in;
        }}

        .triad-nexus-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 0.092in;
            font-weight: 800;
            font-family: 'JetBrains Mono', monospace;
            color: #FFFFFF;
            letter-spacing: 0.05em;
            text-transform: uppercase;
            margin-bottom: 0.08in;
            border-bottom: 1px solid rgba(255, 255, 255, 0.2);
            padding-bottom: 0.05in;
        }}

        .triad-nexus-row {{
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 0.08in;
        }}

        .triad-node {{
            display: flex;
            flex-direction: column;
            align-items: center;
            text-align: center;
            padding: 0.07in 0.04in;
            border-radius: 0.09in;
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid rgba(255, 255, 255, 0.18);
            position: relative;
            overflow: hidden;
        }}

        .node-bar {{
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 0.035in;
        }}

        .bar-customer {{ background: #3D6BFF; }}
        .bar-seller {{ background: #AB47BC; }}
        .bar-rider {{ background: #26A69A; }}

        .node-icon-wrap {{
            width: 0.32in;
            height: 0.32in;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin-bottom: 0.04in;
        }}

        .node-title {{
            font-size: 0.102in;
            font-weight: 900;
            color: #FFFFFF;
            letter-spacing: 0.03em;
            text-transform: uppercase;
            margin-bottom: 0.02in;
        }}

        .node-sub {{
            font-size: 0.078in;
            font-weight: 600;
            color: #E2E8F0;
            line-height: 1.25;
        }}

        /* Front Bottom Call-to-Action */
        .front-bottom {{
            z-index: 2;
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 0.06in;
        }}

        .flip-prompt {{
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 0.08in;
            background: linear-gradient(135deg, #FF6B35, #FF8C42);
            color: #FFFFFF;
            font-size: 0.115in;
            font-weight: 900;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            padding: 0.08in 0.2in;
            border-radius: 100px;
            border: 1.5px solid rgba(255, 255, 255, 0.5);
            width: 100%;
        }}

        .front-coords {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.082in;
            color: rgba(255, 255, 255, 0.85);
            font-weight: 600;
            letter-spacing: 0.04em;
        }}

        /* ==========================================================================
           SIDE B: THE BACK (BIG QR & MAXIMUM READABILITY)
           ========================================================================== */
        .card-back {{
            background: var(--surface-light);
            color: var(--text-main);
            padding: 0.16in 0.22in 0.14in;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            position: relative;
        }}

        .back-top-stripe {{
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 0.045in;
            background: linear-gradient(90deg, #0F1E80 0%, #1E3FD8 35%, #6A1B9A 70%, #00695C 100%);
        }}

        /* Back Header */
        .back-header {{
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-top: 0.03in;
            margin-bottom: 0.05in;
            border-bottom: 2px solid #E2E6F2;
            padding-bottom: 0.05in;
        }}

        .back-title-group h2 {{
            font-size: 0.22in;
            font-weight: 900;
            letter-spacing: -0.02em;
            color: #0F1E80;
            line-height: 1.1;
            margin: 0;
        }}

        .back-title-group p {{
            font-size: 0.102in;
            font-weight: 600;
            color: var(--text-muted);
            margin-top: 0.02in;
        }}

        .back-brand-tag {{
            display: flex;
            align-items: center;
            gap: 0.04in;
            background: #FFFFFF;
            border: 1.5px solid #CBD5E1;
            padding: 0.04in 0.09in;
            border-radius: 0.06in;
        }}

        .back-brand-tag span {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.088in;
            font-weight: 800;
            color: #1E3FD8;
        }}

        /* The 3 Pillars Section */
        .ecosystem-pillars {{
            display: flex;
            flex-direction: column;
            gap: 0.065in;
            margin-bottom: 0.05in;
        }}

        .pillar-row {{
            display: flex;
            align-items: center;
            background: #FFFFFF;
            border-radius: 0.11in;
            padding: 0.075in 0.1in;
            border: 1.5px solid var(--border-card);
            position: relative;
            overflow: hidden;
        }}

        .pillar-accent-edge {{
            position: absolute;
            left: 0;
            top: 0;
            bottom: 0;
            width: 0.05in;
        }}

        .pillar-icon-box {{
            width: 0.42in;
            height: 0.42in;
            border-radius: 0.09in;
            display: flex;
            align-items: center;
            justify-content: center;
            margin-left: 0.04in;
            margin-right: 0.1in;
            flex-shrink: 0;
        }}

        .pillar-icon-box svg {{
            width: 0.25in;
            height: 0.25in;
            fill: #FFFFFF;
        }}

        .pillar-details {{
            display: flex;
            flex-direction: column;
            flex: 1;
        }}

        .pillar-headline-row {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 0.02in;
        }}

        .pillar-role {{
            font-size: 0.145in;
            font-weight: 900;
            letter-spacing: -0.01em;
            color: var(--text-main);
        }}

        .pillar-badge {{
            font-size: 0.082in;
            font-weight: 800;
            letter-spacing: 0.04em;
            text-transform: uppercase;
            padding: 0.02in 0.06in;
            border-radius: 0.04in;
        }}

        .badge-customer-style {{
            background: var(--customer-tint);
            color: var(--customer-color);
            border: 1px solid rgba(30, 63, 216, 0.25);
        }}

        .badge-seller-style {{
            background: var(--seller-tint);
            color: var(--seller-color);
            border: 1px solid rgba(106, 27, 154, 0.25);
        }}

        .badge-rider-style {{
            background: var(--rider-tint);
            color: var(--rider-color);
            border: 1px solid rgba(0, 105, 92, 0.25);
        }}

        .pillar-perks {{
            font-size: 0.096in;
            font-weight: 600;
            color: var(--text-muted);
            line-height: 1.25;
            display: flex;
            align-items: center;
            gap: 0.06in;
        }}

        .pillar-perks span.bullet {{
            color: var(--secondary);
            font-weight: 900;
        }}

        /* Universal QR Download Vault */
        .qr-vault {{
            background: linear-gradient(135deg, #050B3B 0%, #0F1E80 100%);
            color: #FFFFFF;
            border-radius: 0.15in;
            padding: 0.11in 0.14in;
            display: flex;
            align-items: center;
            gap: 0.15in;
            position: relative;
            overflow: hidden;
            border: 1.5px solid rgba(255, 255, 255, 0.25);
        }}

        /* EXTRA-LARGE QR FRAME (1.6in x 1.6in) */
        .qr-frame {{
            width: 1.6in;
            height: 1.6in;
            background: #FFFFFF;
            border-radius: 0.1in;
            padding: 0.07in;
            position: relative;
            flex-shrink: 0;
            display: flex;
            align-items: center;
            justify-content: center;
        }}

        /* Reticle Laser Corners */
        .reticle-corner {{
            position: absolute;
            width: 0.12in;
            height: 0.12in;
            border-color: #1E3FD8;
            border-style: solid;
        }}
        .reticle-tl {{ top: 0.03in; left: 0.03in; border-width: 2.5px 0 0 2.5px; border-top-left-radius: 0.04in; }}
        .reticle-tr {{ top: 0.03in; right: 0.03in; border-width: 2.5px 2.5px 0 0; border-top-right-radius: 0.04in; }}
        .reticle-bl {{ bottom: 0.03in; left: 0.03in; border-width: 0 0 2.5px 2.5px; border-bottom-left-radius: 0.04in; }}
        .reticle-br {{ bottom: 0.03in; right: 0.03in; border-width: 0 2.5px 2.5px 0; border-bottom-right-radius: 0.04in; }}

        .qr-image {{
            width: 100%;
            height: 100%;
            object-fit: contain;
            display: block;
            image-rendering: -webkit-optimize-contrast;
            image-rendering: crisp-edges;
        }}

        .qr-meta {{
            display: flex;
            flex-direction: column;
            justify-content: center;
            flex: 1;
            z-index: 1;
            gap: 0.05in;
        }}

        .qr-headline {{
            font-size: 0.18in;
            font-weight: 900;
            letter-spacing: -0.01em;
            color: #FFFFFF;
            line-height: 1.1;
        }}

        .qr-sub {{
            font-size: 0.102in;
            font-weight: 600;
            color: #E2E8F0;
            line-height: 1.3;
        }}

        /* App Store Vector Badges */
        .store-badges {{
            display: flex;
            gap: 0.07in;
            align-items: center;
            margin-top: 0.02in;
        }}

        .store-pill {{
            display: flex;
            align-items: center;
            gap: 0.05in;
            background: rgba(255, 255, 255, 0.18);
            border: 1px solid rgba(255, 255, 255, 0.35);
            padding: 0.04in 0.09in;
            border-radius: 0.06in;
        }}

        .store-pill svg {{
            width: 0.13in;
            height: 0.13in;
            fill: #FFFFFF;
        }}

        .store-pill span {{
            font-size: 0.09in;
            font-weight: 800;
            color: #FFFFFF;
            letter-spacing: 0.02em;
        }}

        /* DEDICATED CONTACT & HELPLINE BAR */
        .contact-strip {{
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 0.07in;
            background: #FFFFFF;
            border: 1.5px solid var(--border-card);
            border-radius: 0.09in;
            padding: 0.05in 0.1in;
            margin-top: 0.05in;
        }}

        .contact-phone-icon {{
            width: 0.14in;
            height: 0.14in;
            fill: #FF6B35;
            flex-shrink: 0;
        }}

        .contact-label {{
            font-size: 0.088in;
            font-weight: 800;
            color: #0F1E80;
            text-transform: uppercase;
            letter-spacing: 0.04em;
            font-family: 'JetBrains Mono', monospace;
        }}

        .contact-numbers {{
            display: flex;
            align-items: center;
            gap: 0.06in;
        }}

        .phone-item {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.105in;
            font-weight: 800;
            color: #0B1220;
            text-decoration: none;
            letter-spacing: 0.01em;
        }}

        .phone-dot {{
            color: #FF6B35;
            font-weight: 900;
            font-size: 0.095in;
        }}

        /* Bottom Contact & Legal Bar */
        .back-footer {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-top: 1.5px solid #E2E6F2;
            padding-top: 0.05in;
            font-size: 0.09in;
            color: var(--text-subtle);
            font-weight: 600;
            margin-top: 0.04in;
        }}

        .footer-left {{
            display: flex;
            align-items: center;
            gap: 0.08in;
            font-weight: 800;
            color: #1E3FD8;
            font-size: 0.095in;
        }}

        .footer-right {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.082in;
            font-weight: 700;
            color: var(--text-muted);
        }}

        /* ==========================================================================
           PRINT OVERRIDES: 1000x FLAWLESS VECTOR PRECISION (ZERO SKIA ARTIFACTS)
           ========================================================================== */
        @media print {{
            html, body {{
                background: none !important;
                padding: 0 !important;
                margin: 0 !important;
                width: 4in !important;
                height: auto !important;
            }}

            .studio-header,
            .preview-controls,
            .card-label,
            .flip-instruction-tag,
            .instructions-banner {{
                display: none !important;
            }}

            .stage-container,
            .stage-container.mode-flip {{
                display: block !important;
                gap: 0 !important;
                perspective: none !important;
                margin: 0 !important;
                padding: 0 !important;
            }}

            .flip-card-3d {{
                display: block !important;
                width: 4in !important;
                height: auto !important;
                transform: none !important;
                transition: none !important;
                transform-style: flat !important;
            }}

            .card-wrapper {{
                display: block !important;
                position: relative !important;
                top: auto !important;
                left: auto !important;
                width: 4in !important;
                height: 6in !important;
                page-break-after: always !important;
                break-after: page !important;
                page-break-inside: avoid !important;
                break-inside: avoid !important;
                transform: none !important;
                backface-visibility: visible !important;
                margin: 0 !important;
                padding: 0 !important;
            }}

            .card-wrapper.back-side-wrap {{
                transform: none !important;
            }}

            .card-canvas {{
                box-shadow: none !important;
                border: none !important;
                border-radius: 0 !important;
                margin: 0 !important;
                width: 4in !important;
                height: 6in !important;
                max-width: 4in !important;
                max-height: 6in !important;
                overflow: hidden !important;
                -webkit-print-color-adjust: exact !important;
                print-color-adjust: exact !important;
            }}

            /* Crucial: Eliminate Skia raster bounding-box artifacts */
            * {{
                text-shadow: none !important;
                -webkit-filter: none !important;
                filter: none !important;
                backdrop-filter: none !important;
                -webkit-backdrop-filter: none !important;
                box-shadow: none !important;
            }}
        }}
    </style>
</head>
<body>

    <!-- Web Preview Chrome -->
    <div class="studio-header">
        <h1>Enything Super-App Master Card</h1>
        <p>Ultra-High Precision Dual-Sided Print Card (4.0" × 6.0" • 2:3 Aspect Ratio • enything.in)</p>
        <div class="badge-pill">
            <span class="dot"></span>
            300 DPI COMMERCIAL PRINT READY • EXTRA LARGE TYPOGRAPHY & BIG QR
        </div>
    </div>

    <!-- Interactive Mode Switchers -->
    <div class="preview-controls">
        <button class="btn btn-secondary active" id="btnSideBySide" onclick="setMode('side-by-side')">
            Side-by-Side Print View
        </button>
        <button class="btn btn-secondary" id="btn3DFlip" onclick="setMode('3d-flip')">
            3D Interactive Pass (Click to Flip)
        </button>
        <button class="btn btn-primary" onclick="window.print()">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                <path d="M19 8H5c-1.66 0-3 1.34-3 3v6h4v4h12v-4h4v-6c0-1.66-1.34-3-3-3zm-3 11H8v-5h8v5zm3-7c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1zm-1-9H6v4h12V3z"/>
            </svg>
            Print / Save Print-Ready PDF (4x6)
        </button>
    </div>

    <!-- Physical Stage: Side A and Side B -->
    <div class="stage-container" id="stageContainer">
        <div class="flip-card-3d" id="flipCard3d" onclick="toggleFlip()">

            <!-- ================= PAGE 1: SIDE A (THE FRONT) ================= -->
            <div class="card-wrapper front-side-wrap">
                <div class="card-label">FRONT SIDE // THE IDENTITY</div>
                <div class="card-canvas card-front">
                    
                    <div class="bg-mesh-grid"></div>
                    
                    <!-- Front Meta Bar -->
                    <div class="front-meta-bar">
                        <div class="chip-emblem">
                            <div class="sim-chip"></div>
                            <svg class="nfc-icon" viewBox="0 0 24 24">
                                <path d="M4 12a8 8 0 0 1 8-8v2a6 6 0 0 0-6 6h-2zm4 0a4 4 0 0 1 4-4v2a2 2 0 0 0-2 2h-2zm12 0a12 12 0 0 0-12-12v2a10 10 0 0 1 10 10h2z"/>
                            </svg>
                        </div>
                        <div class="pass-badge">HYPERLOCAL PASS // 2026</div>
                    </div>

                    <!-- Hero Branding -->
                    <div class="front-hero">
                        <div class="app-emblem-container">
                            <img src="{logo_b64 if logo_b64 else 'logo/Enything_modern.png'}" alt="Enything Emblem" class="emblem-img" onerror="this.src='logo/Enything_modern.png'">
                        </div>
                        
                        <h1 class="brand-title">Enything</h1>
                        
                        <div class="brand-pill">
                            <span class="brand-pill-text">THE SUPER-APP OF TOMORROW</span>
                        </div>

                        <p class="tagline-hero">
                            Everything. Everywhere.<br>
                            <span class="accent">Instantly.</span>
                        </p>
                    </div>

                    <!-- Triad Nexus (Harmonic Ecosystem) -->
                    <div class="triad-nexus">
                        <div class="triad-nexus-header">
                            <span>THE CONVERGED TRIAD</span>
                            <span>SINGLE PLATFORM</span>
                        </div>
                        <div class="triad-nexus-row">
                            <!-- Node 1 -->
                            <div class="triad-node">
                                <div class="node-bar bar-customer"></div>
                                <div class="node-icon-wrap" style="background: rgba(61, 107, 255, 0.25);">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="#3D6BFF">
                                        <path d="M19 6h-2c0-2.76-2.24-5-5-5S7 3.24 7 6H5c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zm-7-3c1.66 0 3 1.34 3 3H9c0-1.66 1.34-3 3-3zm7 17H5V8h14v12zm-7-8c-1.66 0-3-1.34-3-3H7c0 2.76 2.24 5 5 5s5-2.24 5-5h-2c0 1.66-1.34 3-3 3z"/>
                                    </svg>
                                </div>
                                <div class="node-title">CUSTOMERS</div>
                                <div class="node-sub">Shop & Savor In Minutes</div>
                            </div>

                            <!-- Node 2: SELLERS -->
                            <div class="triad-node">
                                <div class="node-bar bar-seller"></div>
                                <div class="node-icon-wrap" style="background: rgba(171, 71, 188, 0.25);">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="#AB47BC">
                                        <path d="M20 4H4v2h16V4zm1 10v-2l-1-5H4l-1 5v2h1v6h10v-6h4v6h2v-6h1zm-9 4H6v-4h6v4z"/>
                                    </svg>
                                </div>
                                <div class="node-title">SELLERS</div>
                                <div class="node-sub">Scale Local Commerce</div>
                            </div>

                            <!-- Node 3: RIDERS -->
                            <div class="triad-node">
                                <div class="node-bar bar-rider"></div>
                                <div class="node-icon-wrap" style="background: rgba(38, 166, 154, 0.25);">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="#26A69A">
                                        <path d="M15.5 5.5c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zM5 12c-2.8 0-5 2.2-5 5s2.2 5 5 5 5-2.2 5-5-2.2-5-5-5zm0 8.5c-1.9 0-3.5-1.6-3.5-3.5s1.6-3.5 3.5-3.5 3.5 1.6 3.5 3.5-1.6 3.5-3.5 3.5zm14-8.5c-2.8 0-5 2.2-5 5s2.2 5 5 5 5-2.2 5-5-2.2-5-5-5zm0 8.5c-1.9 0-3.5-1.6-3.5-3.5s1.6-3.5 3.5-3.5 3.5 1.6 3.5 3.5-1.6 3.5-3.5 3.5zm-8.2-7.2l-2.4-2.4c-.4-.4-.9-.6-1.4-.6h-3v2h2.6l1.8 1.8-3.4 3.4 1.4 1.4 3.6-3.6 2.4 2.4v4.2h2v-5c0-.6-.2-1.1-.6-1.6z"/>
                                    </svg>
                                </div>
                                <div class="node-title">RIDERS</div>
                                <div class="node-sub">High Earnings & Freedom</div>
                            </div>
                        </div>
                    </div>

                    <!-- Front Bottom Call to Action -->
                    <div class="front-bottom">
                        <div class="flip-prompt">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                                <path d="M12 4V1L8 5l4 4V6c3.31 0 6 2.69 6 6 0 1.01-.25 1.97-.7 2.8l1.46 1.46C19.54 15.03 20 13.57 20 12c0-4.42-3.58-8-8-8zm0 14c-3.31 0-6-2.69-6-6 0-1.01.25-1.97.7-2.8L5.24 7.74C4.46 8.97 4 10.43 4 12c0 4.42 3.58 8 8 8v3l4-4-4-4v3z"/>
                            </svg>
                            Flip Card To Download & Join
                        </div>
                        <div class="front-coords">DISPATCH GEN-26 // 34.0837° N, 74.7973° E // enything.in</div>
                    </div>

                </div>
            </div>

            <!-- ================= PAGE 2: SIDE B (THE BACK) ================= -->
            <div class="card-wrapper back-side-wrap">
                <div class="card-label">BACK SIDE // THE PORTAL</div>
                <div class="card-canvas card-back">
                    <div class="back-top-stripe"></div>

                    <!-- Back Header -->
                    <div class="back-header">
                        <div class="back-title-group">
                            <h2>One App. Infinite Reach.</h2>
                            <p>Your entire city's commerce connected in real-time.</p>
                        </div>
                        <div class="back-brand-tag">
                            <span>ENYTHING.IN</span>
                        </div>
                    </div>

                    <!-- The 3 Pillars (Structured, Bold, Clear) -->
                    <div class="ecosystem-pillars">

                        <!-- 1. Customer Pillar -->
                        <div class="pillar-row">
                            <div class="pillar-accent-edge" style="background: var(--customer-gradient);"></div>
                            <div class="pillar-icon-box" style="background: var(--customer-gradient);">
                                <svg viewBox="0 0 24 24">
                                    <path d="M7 18c-1.1 0-1.99.9-1.99 2S5.9 22 7 22s2-.9 2-2-.9-2-2-2zM1 2v2h2l3.6 7.59-1.35 2.45c-.16.28-.25.61-.25.96 0 1.1.9 2 2 2h12v-2H7.42c-.14 0-.25-.11-.25-.25l.03-.12.9-1.63h7.45c.75 0 1.41-.41 1.75-1.03l3.58-6.49c.08-.14.12-.31.12-.48 0-.55-.45-1-1-1H5.21l-.94-2H1zm16 16c-1.1 0-1.99.9-1.99 2s.89 2 1.99 2 2-.9 2-2-.9-2-2-2z"/>
                                </svg>
                            </div>
                            <div class="pillar-details">
                                <div class="pillar-headline-row">
                                    <span class="pillar-role">For Customers</span>
                                    <span class="pillar-badge badge-customer-style">SHOP & SAVOR</span>
                                </div>
                                <div class="pillar-perks">
                                    <span>Restaurants <span class="bullet">•</span> 10-Min Groceries <span class="bullet">•</span> Pharmacy <span class="bullet">•</span> Live GPS</span>
                                </div>
                            </div>
                        </div>

                        <!-- 2. Seller Pillar (Named as Sellers) -->
                        <div class="pillar-row">
                            <div class="pillar-accent-edge" style="background: var(--seller-gradient);"></div>
                            <div class="pillar-icon-box" style="background: var(--seller-gradient);">
                                <svg viewBox="0 0 24 24">
                                    <path d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10zm-2-8h-2v2h2v-2zm0 4h-2v2h2v-2z"/>
                                </svg>
                            </div>
                            <div class="pillar-details">
                                <div class="pillar-headline-row">
                                    <span class="pillar-role">For Sellers</span>
                                    <span class="pillar-badge badge-seller-style">SELL & SCALE</span>
                                </div>
                                <div class="pillar-perks">
                                    <span>Zero Upfront Fee <span class="bullet">•</span> Direct Settlements <span class="bullet">•</span> Automated Dispatch</span>
                                </div>
                            </div>
                        </div>

                        <!-- 3. Rider Pillar -->
                        <div class="pillar-row">
                            <div class="pillar-accent-edge" style="background: var(--rider-gradient);"></div>
                            <div class="pillar-icon-box" style="background: var(--rider-gradient);">
                                <svg viewBox="0 0 24 24">
                                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/>
                                </svg>
                            </div>
                            <div class="pillar-details">
                                <div class="pillar-headline-row">
                                    <span class="pillar-role">For Delivery Partners</span>
                                    <span class="pillar-badge badge-rider-style">MOVE & EARN</span>
                                </div>
                                <div class="pillar-perks">
                                    <span>Flexible Hours <span class="bullet">•</span> Peak Surge Multipliers <span class="bullet">•</span> Daily Fast Payouts</span>
                                </div>
                            </div>
                        </div>

                    </div>

                    <!-- Extra-Large High Precision QR Download Hub -->
                    <div class="qr-vault">
                        <!-- Extra-Large Reticle Frame (1.6in x 1.6in) with User QR -->
                        <div class="qr-frame">
                            <div class="reticle-corner reticle-tl"></div>
                            <div class="reticle-corner reticle-tr"></div>
                            <div class="reticle-corner reticle-bl"></div>
                            <div class="reticle-corner reticle-br"></div>
                            <img src="{qr_b64 if qr_b64 else 'my_qr_code.png'}" alt="Scan to Download Enything" class="qr-image" onerror="this.src='my_qr_code.png'">
                        </div>

                        <!-- Action Details with Larger Typography -->
                        <div class="qr-meta">
                            <div class="qr-headline">Scan To Download</div>
                            <div class="qr-sub">Instant access for Customers, Sellers & Delivery Partners.</div>

                            <div class="store-badges">
                                <div class="store-pill">
                                    <svg viewBox="0 0 24 24">
                                        <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.37c.62-.75 1.04-1.8 1.01-2.85-.9.04-2 .6-2.65 1.35-.58.66-1.09 1.73-1.04 2.76 1 .08 2.06-.51 2.68-1.26z"/>
                                    </svg>
                                    <span>iOS</span>
                                </div>
                                <div class="store-pill">
                                    <svg viewBox="0 0 24 24">
                                        <path d="M3.609 1.814L13.792 12 3.61 22.186a1.59 1.59 0 0 1-.61-.314 1.576 1.576 0 0 1-.492-1.15V3.278c0-.442.174-.863.492-1.15.19-.17.397-.278.609-.314zm11.235 11.238l2.583 2.583-11.455 6.46 8.872-9.043zm2.583-2.052l-2.583 2.583L5.972 4.54l11.455 6.46zm1.095.617l3.208 1.808a1.188 1.188 0 0 1 0 2.066l-3.208 1.808-2.666-2.841 2.666-2.841z"/>
                                    </svg>
                                    <span>Android</span>
                                </div>
                            </div>
                        </div>

                    </div>

                    <!-- Prominent Contact & Helpline Strip with Both Phone Numbers -->
                    <div class="contact-strip">
                        <svg class="contact-phone-icon" viewBox="0 0 24 24">
                            <path d="M6.62 10.79a15.053 15.053 0 0 0 6.59 6.59l2.2-2.2a1 1 0 0 1 1.02-.24c1.12.37 2.33.57 3.57.57a1 1 0 0 1 1 1V20a1 1 0 0 1-1 1A17 17 0 0 1 3 4a1 1 0 0 1 1-1h3.5a1 1 0 0 1 1 1c0 1.25.2 2.45.57 3.57a1 1 0 0 1-.25 1.02l-2.2 2.2z"/>
                        </svg>
                        <span class="contact-label">Helpline:</span>
                        <div class="contact-numbers">
                            <a href="tel:+917006464241" class="phone-item">+91 70064 64241</a>
                            <span class="phone-dot">•</span>
                            <a href="tel:+917006029318" class="phone-item">+91 70060 29318</a>
                        </div>
                    </div>

                    <!-- Footer with enything.in & support@enything.in -->
                    <div class="back-footer">
                        <div class="footer-left">
                            <span>enything.in</span>
                            <span>•</span>
                            <span>support@enything.in</span>
                        </div>
                        <div class="footer-right">
                            © 2026 ENYTHING SUPER-APP
                        </div>
                    </div>

                </div>
            </div>

        </div>
    </div>
    
    <div class="flip-instruction-tag">👆 Click the card to flip between Front & Back</div>

    <script>
        let currentMode = 'side-by-side';
        let isFlipped = false;

        function setMode(mode) {{
            currentMode = mode;
            const container = document.getElementById('stageContainer');
            const flipCard = document.getElementById('flipCard3d');
            const btnSide = document.getElementById('btnSideBySide');
            const btnFlip = document.getElementById('btn3DFlip');

            if (mode === '3d-flip') {{
                container.classList.add('mode-flip');
                btnSide.classList.remove('active');
                btnFlip.classList.add('active');
            }} else {{
                container.classList.remove('mode-flip');
                btnSide.classList.add('active');
                btnFlip.classList.remove('active');
                flipCard.classList.remove('flipped');
                isFlipped = false;
            }}
        }}

        function toggleFlip() {{
            if (currentMode !== '3d-flip') return;
            const flipCard = document.getElementById('flipCard3d');
            isFlipped = !isFlipped;
            if (isFlipped) {{
                flipCard.classList.add('flipped');
            }} else {{
                flipCard.classList.remove('flipped');
            }}
        }}
    </script>

</body>
</html>
'''

# Write to all card files so user sees it in whichever tab they have open
with open('enything_card_ultimate.html', 'w') as f:
    f.write(html_content)

with open('enything_seller_print_card.html', 'w') as f:
    f.write(html_content)

with open('enything_universal_card.html', 'w') as f:
    f.write(html_content)

print("Successfully updated with flawless print rules & local fonts!")
