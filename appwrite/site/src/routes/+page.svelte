<script>
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';

  let endpoints = [
    {
      method: 'POST',
      path: '/api/search_scripts',
      description: 'Search for scripts with filters and pagination',
      parameters: ['query', 'category', 'canisterId', 'minRating', 'maxPrice', 'sortBy', 'limit', 'offset']
    },
    {
      method: 'POST',
      path: '/api/process_purchase',
      description: 'Process script purchases and update download counts',
      parameters: ['userId', 'scriptId', 'paymentMethod', 'price', 'transactionId']
    },
    {
      method: 'POST',
      path: '/api/update_script_stats',
      description: 'Update script statistics when new reviews are added',
      parameters: ['payload (event data)']
    },
    {
      method: 'GET',
      path: '/api/get_marketplace_stats',
      description: 'Get marketplace statistics and analytics',
      parameters: []
    }
  ];

  let isDark = false;

  onMount(() => {
    // Add smooth scroll behavior
    document.documentElement.style.scrollBehavior = 'smooth';

    // Check system color preference
    if (browser) {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      isDark = mediaQuery.matches;

      // Listen for system theme changes
      const handleChange = (e) => {
        isDark = e.matches;
      };

      mediaQuery.addEventListener('change', handleChange);

      return () => {
        mediaQuery.removeEventListener('change', handleChange);
      };
    }
  });

  $: if (browser) {
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
  }

  function toggleTheme() {
    isDark = !isDark;
  }
</script>

<svelte:head>
  <style>
    :root {
      /* Light theme colors - Modern 2025 palette */
      --bg-primary: #fafbfc;
      --bg-secondary: #ffffff;
      --bg-accent: #f8faff;
      --text-primary: #0d1117;
      --text-secondary: #656d76;
      --text-muted: #8b949e;
      --text-inverse: #ffffff;
      --accent-primary: #0969da;
      --accent-secondary: #1a7f37;
      --accent-tertiary: #8250df;
      --accent-warning: #bf8700;
      --accent-coral: #cf222e;
      --accent-teal: #1f883d;
      --border-color: #d1d9e0;
      --shadow-sm: 0 2px 8px rgba(0, 0, 0, 0.06);
      --shadow-md: 0 4px 16px rgba(0, 0, 0, 0.08);
      --shadow-lg: 0 8px 32px rgba(0, 0, 0, 0.12);
      --shadow-xl: 0 16px 64px rgba(0, 0, 0, 0.16);
      --gradient-primary: linear-gradient(135deg, #0969da 0%, #8250df 50%, #cf222e 100%);
      --gradient-accent: linear-gradient(135deg, #1a7f37 0%, #0969da 100%);
      --gradient-hero: linear-gradient(135deg, #0d1117 0%, #161b22 50%, #21262d 100%);
    }

    [data-theme="dark"] {
      /* Dark theme colors - Modern 2025 palette */
      --bg-primary: #010409;
      --bg-secondary: #0d1117;
      --bg-accent: #161b22;
      --text-primary: #f0f6fc;
      --text-secondary: #c9d1d9;
      --text-muted: #8b949e;
      --text-inverse: #010409;
      --accent-primary: #58a6ff;
      --accent-secondary: #3fb950;
      --accent-tertiary: #bc8cff;
      --accent-warning: #f79009;
      --accent-coral: #f85149;
      --accent-teal: #2ea043;
      --border-color: #30363d;
      --shadow-sm: 0 2px 8px rgba(0, 0, 0, 0.24);
      --shadow-md: 0 4px 16px rgba(0, 0, 0, 0.32);
      --shadow-lg: 0 8px 32px rgba(0, 0, 0, 0.48);
      --shadow-xl: 0 16px 64px rgba(0, 0, 0, 0.64);
      --gradient-primary: linear-gradient(135deg, #58a6ff 0%, #bc8cff 50%, #f85149 100%);
      --gradient-accent: linear-gradient(135deg, #3fb950 0%, #58a6ff 100%);
      --gradient-hero: linear-gradient(135deg, #010409 0%, #0d1117 50%, #161b22 100%);
    }

    :global(body) {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'SF Pro Display', 'Inter', sans-serif;
      background: var(--gradient-hero);
      min-height: 100vh;
      color: var(--text-primary);
      line-height: 1.7;
      letter-spacing: -0.01em;
      transition: background 0.4s cubic-bezier(0.25, 0.46, 0.45, 0.94), color 0.4s cubic-bezier(0.25, 0.46, 0.45, 0.94);
      font-weight: 400;
    }

    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 0 20px;
    }

    .hero {
      text-align: center;
      padding: 100px 20px;
      color: var(--text-inverse);
      position: relative;
      overflow: hidden;
    }

    .hero::before {
      content: '';
      position: absolute;
      top: -50%;
      left: -50%;
      width: 200%;
      height: 200%;
      background: radial-gradient(circle, rgba(255, 255, 255, 0.03) 0%, transparent 70%);
      animation: float 20s ease-in-out infinite;
    }

    .hero h1 {
      font-size: 4rem;
      font-weight: 700;
      margin-bottom: 28px;
      text-shadow: 0 4px 24px rgba(0, 0, 0, 0.2);
      animation: fadeInUp 0.9s cubic-bezier(0.34, 1.56, 0.64, 1);
      background: linear-gradient(135deg, rgba(255, 255, 255, 0.98) 0%, rgba(255, 255, 255, 0.92) 50%, rgba(255, 255, 255, 0.86) 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
      position: relative;
      z-index: 1;
    }

    .hero .subtitle {
      font-size: 1.375rem;
      margin-bottom: 48px;
      opacity: 0.94;
      max-width: 680px;
      margin-left: auto;
      margin-right: auto;
      animation: fadeInUp 0.9s cubic-bezier(0.34, 1.56, 0.64, 1) 0.15s both;
      font-weight: 400;
      text-shadow: 0 2px 12px rgba(0, 0, 0, 0.15);
      line-height: 1.8;
      position: relative;
      z-index: 1;
    }

    .features {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(360px, 1fr));
      gap: 40px;
      margin: 120px 0;
      animation: fadeInUp 0.9s cubic-bezier(0.34, 1.56, 0.64, 1) 0.3s both;
      position: relative;
    }

    .feature-card {
      background: var(--bg-secondary);
      backdrop-filter: blur(24px);
      border-radius: 24px;
      padding: 40px 36px;
      box-shadow: var(--shadow-xl);
      border: 1px solid var(--border-color);
      transition: all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
      position: relative;
      overflow: hidden;
      transform-style: preserve-3d;
    }

    .feature-card::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 4px;
      background: var(--gradient-accent);
      transform: scaleX(0) translateY(-1px);
      transition: transform 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
      transform-origin: left;
    }

    .feature-card::after {
      content: '';
      position: absolute;
      top: -50%;
      left: -50%;
      width: 200%;
      height: 200%;
      background: radial-gradient(circle, var(--accent-primary) 0%, transparent 70%);
      opacity: 0;
      transition: opacity 0.4s ease;
      pointer-events: none;
    }

    .feature-card:hover::before {
      transform: scaleX(1);
    }

    .feature-card:hover {
      transform: translateY(-12px) rotateX(2deg);
      box-shadow: 0 24px 80px rgba(0, 0, 0, 0.18);
      border-color: var(--accent-primary);
    }

    .feature-card:hover::after {
      opacity: 0.03;
    }

    .feature-card h3 {
      color: var(--accent-primary);
      margin-top: 0;
      margin-bottom: 16px;
      font-size: 1.5rem;
      font-weight: 700;
    }

    .feature-card p {
      color: var(--text-secondary);
      margin-bottom: 16px;
      font-weight: 400;
    }

    .feature-card strong {
      color: var(--accent-secondary);
      font-weight: 600;
    }

    .api-section {
      background: var(--bg-secondary);
      border-radius: 28px;
      padding: 60px;
      margin: 120px 0;
      box-shadow: var(--shadow-xl);
      border: 1px solid var(--border-color);
      animation: fadeInUp 0.9s cubic-bezier(0.34, 1.56, 0.64, 1) 0.45s both;
      position: relative;
      overflow: hidden;
    }

    .api-section::before {
      content: '';
      position: absolute;
      top: -100px;
      right: -100px;
      width: 200px;
      height: 200px;
      background: radial-gradient(circle, var(--accent-primary) 0%, transparent 70%);
      opacity: 0.05;
      animation: pulse 4s ease-in-out infinite;
    }

    .api-section h2 {
      text-align: center;
      color: var(--text-primary);
      margin-bottom: 56px;
      font-size: 2.75rem;
      font-weight: 600;
      position: relative;
      z-index: 1;
    }

    .api-section > p {
      text-align: center;
      color: var(--text-secondary);
      margin-bottom: 48px;
      font-size: 1.125rem;
      max-width: 800px;
      margin-left: auto;
      margin-right: auto;
    }

    .endpoint-grid {
      display: grid;
      gap: 24px;
    }

    .endpoint-card {
      background: var(--bg-accent);
      border-left: 4px solid var(--accent-primary);
      border-radius: 20px;
      padding: 32px 28px;
      transition: all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
      border: 1px solid var(--border-color);
      position: relative;
      overflow: hidden;
      transform-style: preserve-3d;
    }

    .endpoint-card::before {
      content: '';
      position: absolute;
      top: 0;
      right: 0;
      width: 0;
      height: 0;
      background: var(--accent-primary);
      clip-path: polygon(0 0, 100% 0, 100% 100%);
      opacity: 0.08;
      transition: all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
    }

    .endpoint-card:hover {
      background: var(--bg-secondary);
      transform: translateX(12px) translateY(-2px) rotateY(2deg);
      box-shadow: var(--shadow-xl);
      border-color: var(--accent-primary);
      border-radius: 24px;
    }

    .endpoint-card:hover::before {
      width: 60px;
      height: 60px;
    }

    .endpoint-header {
      display: flex;
      align-items: center;
      margin-bottom: 16px;
      flex-wrap: wrap;
      gap: 12px;
    }

    .method {
      color: var(--text-inverse);
      padding: 6px 14px;
      border-radius: 20px;
      font-size: 0.75rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      box-shadow: var(--shadow-sm);
    }

    .method.post {
      background: var(--accent-secondary);
      box-shadow: 0 4px 16px rgba(26, 127, 55, 0.24);
    }
    .method.get {
      background: var(--accent-primary);
      box-shadow: 0 4px 16px rgba(9, 105, 218, 0.24);
    }

    .method:hover {
      transform: translateY(-2px);
      box-shadow: 0 6px 20px rgba(0, 0, 0, 0.16);
    }

    .path {
      font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', 'Menlo', monospace;
      background: var(--bg-primary);
      color: var(--accent-primary);
      padding: 10px 18px;
      border-radius: 12px;
      font-size: 0.9rem;
      font-weight: 500;
      border: 1px solid var(--border-color);
      transition: all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
      letter-spacing: 0.025em;
    }

    .path:hover {
      background: var(--accent-primary);
      color: var(--text-inverse);
      transform: translateY(-1px);
      box-shadow: 0 4px 12px rgba(9, 105, 218, 0.32);
    }

    .endpoint-description {
      color: var(--text-secondary);
      line-height: 1.6;
      margin-bottom: 16px;
    }

    .parameters {
      margin-top: 16px;
    }

    .parameters h4 {
      color: var(--text-primary);
      margin-bottom: 8px;
      font-size: 0.875rem;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      font-weight: 600;
    }

    .param-tags {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }

    .param-tag {
      background: var(--bg-primary);
      color: var(--text-secondary);
      padding: 4px 12px;
      border-radius: 12px;
      font-size: 0.75rem;
      font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace;
      border: 1px solid var(--border-color);
    }

    .coming-soon {
      text-align: center;
      padding: 80px 20px;
      color: var(--text-inverse);
      animation: fadeInUp 0.8s ease-out 0.8s both;
    }

    .coming-soon h2 {
      font-size: 2.5rem;
      margin-bottom: 24px;
      font-weight: 700;
    }

    .coming-soon p {
      font-size: 1.125rem;
      opacity: 0.95;
      max-width: 600px;
      margin: 0 auto 24px;
      text-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
    }

    .beta-badge {
      display: inline-block;
      background: var(--accent-warning);
      color: var(--text-primary);
      padding: 8px 16px;
      border-radius: 20px;
      font-size: 0.75rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      margin-left: 12px;
      box-shadow: var(--shadow-sm);
    }

    .footer {
      text-align: center;
      padding: 48px 20px;
      color: var(--text-inverse);
      animation: fadeInUp 0.8s ease-out 1s both;
    }

    .footer p {
      margin-bottom: 8px;
      opacity: 0.9;
    }

    .footer strong {
      color: var(--accent-secondary);
      font-weight: 600;
    }

    .theme-toggle {
      position: fixed;
      top: 24px;
      right: 24px;
      background: var(--bg-secondary);
      border: 1px solid var(--border-color);
      border-radius: 16px;
      width: 52px;
      height: 52px;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      box-shadow: var(--shadow-lg);
      transition: all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
      z-index: 1000;
      font-size: 22px;
      backdrop-filter: blur(24px);
    }

    .theme-toggle:hover {
      transform: scale(1.08) rotate(5deg);
      box-shadow: var(--shadow-xl);
      border-color: var(--accent-primary);
      background: var(--accent-primary);
    }

    .theme-toggle:active {
      transform: scale(1.02) rotate(-2deg);
    }

    @media (max-width: 768px) {
      .theme-toggle {
        top: 16px;
        right: 16px;
        width: 40px;
        height: 40px;
        font-size: 16px;
      }
    }

    @keyframes fadeInUp {
      from {
        opacity: 0;
        transform: translateY(40px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
    }

    @keyframes float {
      0%, 100% {
        transform: translate(-50%, -50%) rotate(0deg) scale(1);
      }
      33% {
        transform: translate(-45%, -55%) rotate(120deg) scale(1.05);
      }
      66% {
        transform: translate(-55%, -45%) rotate(240deg) scale(0.95);
      }
    }

    @keyframes pulse {
      0%, 100% {
        opacity: 0.05;
        transform: scale(1);
      }
      50% {
        opacity: 0.08;
        transform: scale(1.1);
      }
    }

    @media (max-width: 768px) {
      .hero h1 {
        font-size: 2.75rem;
        font-weight: 600;
      }

      .hero .subtitle {
        font-size: 1.25rem;
        padding: 0 16px;
      }

      .api-section {
        padding: 48px 32px;
        margin: 80px 0;
      }

      .api-section h2 {
        font-size: 2.25rem;
      }

      .endpoint-header {
        flex-direction: column;
        align-items: flex-start;
        gap: 16px;
      }

      .features {
        grid-template-columns: 1fr;
        gap: 32px;
        margin: 80px 0;
      }

      .feature-card {
        padding: 32px 28px;
      }

      .endpoint-card {
        padding: 28px 24px;
      }
    }

    @media (max-width: 480px) {
      .hero h1 {
        font-size: 2.25rem;
        font-weight: 600;
      }

      .hero {
        padding: 80px 16px;
      }

      .hero .subtitle {
        font-size: 1.125rem;
      }

      .feature-card {
        padding: 28px 24px;
        border-radius: 20px;
      }

      .api-section {
        padding: 40px 24px;
        border-radius: 24px;
      }

      .theme-toggle {
        top: 16px;
        right: 16px;
        width: 44px;
        height: 44px;
        font-size: 18px;
      }

      .container {
        padding: 0 16px;
      }
    }
  </style>
</svelte:head>

<!-- Theme Toggle Button -->
{#if browser}
<button class="theme-toggle" onclick={toggleTheme} aria-label="Toggle theme">
  {#if isDark}
    ☀️
  {:else}
    🌙
  {/if}
</button>
{/if}

<div class="hero">
  <div class="container">
    <h1>ICP Script Marketplace</h1>
    <p class="subtitle">
      Discover, share, and download powerful Lua scripts for Internet Computer applications.
      Automate your workflow with community-driven tools and unleash the full potential of ICP.
    </p>
  </div>
</div>

<div class="container">
  <section class="features">
    <div class="feature-card">
      <h3>🚀 Powerful Automation</h3>
      <p>Access a growing collection of Lua scripts designed specifically for Internet Computer automation and workflow optimization.</p>
      <p><strong>Coming soon:</strong> Download scripts, install guides, and one-click setup</p>
    </div>

    <div class="feature-card">
      <h3>🛡️ Secure & Verified</h3>
      <p>All scripts undergo security review and community verification. Download with confidence knowing each script is tested and approved.</p>
      <p><strong>Coming soon:</strong> User reviews, ratings, and security badges</p>
    </div>

    <div class="feature-card">
      <h3>🌍 Community Driven</h3>
      <p>Built by the ICP community, for the ICP community. Contribute your own scripts or request custom automation solutions.</p>
      <p><strong>Coming soon:</strong> Developer profiles, script submissions, and bounty system</p>
    </div>
  </section>

  <section class="api-section">
    <h2>API Endpoints <span class="beta-badge">Beta</span></h2>
    <p style="text-align: center; color: #666; margin-bottom: 40px; font-size: 1.1rem;">
      Our RESTful API provides programmatic access to marketplace functionality.
      All endpoints return JSON responses and support CORS for web applications.
    </p>

    <div class="endpoint-grid">
      {#each endpoints as endpoint}
        <div class="endpoint-card">
          <div class="endpoint-header">
            <span class="method {endpoint.method.toLowerCase()}">{endpoint.method}</span>
            <span class="path">{endpoint.path}</span>
          </div>
          <p class="endpoint-description">{endpoint.description}</p>
          {#if endpoint.parameters.length > 0}
            <div class="parameters">
              <h4>Parameters:</h4>
              <div class="param-tags">
                {#each endpoint.parameters as param}
                  <span class="param-tag">{param}</span>
                {/each}
              </div>
            </div>
          {/if}
        </div>
      {/each}
    </div>
  </section>

  <section class="coming-soon">
    <h2>🚀 More Coming Soon</h2>
    <p>
      We're actively developing the full marketplace experience including script downloads,
      user authentication, developer tools, and comprehensive documentation.
    </p>
    <p style="font-size: 1rem; opacity: 0.8;">
      <strong>Status:</strong> API v1.0 in Beta • Frontend in Development • Launch Q1 2025
    </p>
  </section>
</div>

<footer class="footer">
  <div class="container">
    <p>&copy; 2025 ICP Script Marketplace. Built with ❤️ for the Internet Computer community.</p>
  </div>
</footer>
