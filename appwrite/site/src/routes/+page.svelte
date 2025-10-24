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
      /* Light theme colors */
      --bg-primary: #fafafa;
      --bg-secondary: #ffffff;
      --bg-accent: #f0f4ff;
      --text-primary: #1a202c;
      --text-secondary: #4a5568;
      --text-muted: #718096;
      --text-inverse: #ffffff;
      --accent-primary: #3b82f6;
      --accent-secondary: #10b981;
      --accent-tertiary: #8b5cf6;
      --accent-warning: #f59e0b;
      --border-color: #e2e8f0;
      --shadow-sm: 0 1px 3px rgba(0, 0, 0, 0.1);
      --shadow-md: 0 4px 6px rgba(0, 0, 0, 0.1);
      --shadow-lg: 0 10px 15px rgba(0, 0, 0, 0.1);
      --shadow-xl: 0 20px 25px rgba(0, 0, 0, 0.1);
      --gradient-primary: linear-gradient(135deg, #3b82f6 0%, #8b5cf6 100%);
      --gradient-accent: linear-gradient(135deg, #10b981 0%, #3b82f6 100%);
    }

    [data-theme="dark"] {
      /* Dark theme colors */
      --bg-primary: #0f172a;
      --bg-secondary: #1e293b;
      --bg-accent: #1e3a8a;
      --text-primary: #f8fafc;
      --text-secondary: #e2e8f0;
      --text-muted: #94a3b8;
      --text-inverse: #0f172a;
      --accent-primary: #60a5fa;
      --accent-secondary: #34d399;
      --accent-tertiary: #a78bfa;
      --accent-warning: #fbbf24;
      --border-color: #334155;
      --shadow-sm: 0 1px 3px rgba(0, 0, 0, 0.3);
      --shadow-md: 0 4px 6px rgba(0, 0, 0, 0.3);
      --shadow-lg: 0 10px 15px rgba(0, 0, 0, 0.3);
      --shadow-xl: 0 20px 25px rgba(0, 0, 0, 0.3);
      --gradient-primary: linear-gradient(135deg, #1e3a8a 0%, #581c87 100%);
      --gradient-accent: linear-gradient(135deg, #064e3b 0%, #1e3a8a 100%);
    }

    :global(body) {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Inter', sans-serif;
      background: var(--gradient-primary);
      min-height: 100vh;
      color: var(--text-primary);
      line-height: 1.6;
      transition: background 0.3s ease, color 0.3s ease;
    }

    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 0 20px;
    }

    .hero {
      text-align: center;
      padding: 80px 20px;
      color: var(--text-inverse);
    }

    .hero h1 {
      font-size: 3.5rem;
      font-weight: 800;
      margin-bottom: 24px;
      text-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
      animation: fadeInUp 0.8s ease-out;
      background: linear-gradient(135deg, rgba(255, 255, 255, 0.95) 0%, rgba(255, 255, 255, 0.85) 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
    }

    .hero .subtitle {
      font-size: 1.25rem;
      margin-bottom: 40px;
      opacity: 0.95;
      max-width: 600px;
      margin-left: auto;
      margin-right: auto;
      animation: fadeInUp 0.8s ease-out 0.2s both;
      font-weight: 400;
      text-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
    }

    .features {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 32px;
      margin-bottom: 80px;
      animation: fadeInUp 0.8s ease-out 0.4s both;
    }

    .feature-card {
      background: var(--bg-secondary);
      backdrop-filter: blur(12px);
      border-radius: 20px;
      padding: 32px;
      box-shadow: var(--shadow-lg);
      border: 1px solid var(--border-color);
      transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      position: relative;
      overflow: hidden;
    }

    .feature-card::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 3px;
      background: var(--gradient-accent);
      transform: scaleX(0);
      transition: transform 0.3s ease;
    }

    .feature-card:hover::before {
      transform: scaleX(1);
    }

    .feature-card:hover {
      transform: translateY(-8px);
      box-shadow: var(--shadow-xl);
      border-color: var(--accent-primary);
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
      border-radius: 24px;
      padding: 48px;
      margin-bottom: 80px;
      box-shadow: var(--shadow-xl);
      border: 1px solid var(--border-color);
      animation: fadeInUp 0.8s ease-out 0.6s both;
    }

    .api-section h2 {
      text-align: center;
      color: var(--text-primary);
      margin-bottom: 48px;
      font-size: 2.25rem;
      font-weight: 700;
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
      border-radius: 16px;
      padding: 24px;
      transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      border: 1px solid var(--border-color);
      position: relative;
    }

    .endpoint-card:hover {
      background: var(--bg-secondary);
      transform: translateX(8px);
      box-shadow: var(--shadow-md);
      border-color: var(--accent-primary);
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
    }
    .method.get {
      background: var(--accent-primary);
    }

    .path {
      font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace;
      background: var(--bg-primary);
      color: var(--accent-secondary);
      padding: 8px 16px;
      border-radius: 8px;
      font-size: 0.875rem;
      font-weight: 500;
      border: 1px solid var(--border-color);
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
      top: 20px;
      right: 20px;
      background: var(--bg-secondary);
      border: 1px solid var(--border-color);
      border-radius: 50%;
      width: 48px;
      height: 48px;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      box-shadow: var(--shadow-md);
      transition: all 0.3s ease;
      z-index: 1000;
      font-size: 20px;
    }

    .theme-toggle:hover {
      transform: scale(1.1);
      box-shadow: var(--shadow-lg);
      border-color: var(--accent-primary);
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
        transform: translateY(30px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
    }

    @media (max-width: 768px) {
      .hero h1 {
        font-size: 2.5rem;
      }

      .hero .subtitle {
        font-size: 1.125rem;
      }

      .api-section {
        padding: 32px 24px;
      }

      .endpoint-header {
        flex-direction: column;
        align-items: flex-start;
      }

      .features {
        grid-template-columns: 1fr;
      }
    }

    @media (max-width: 480px) {
      .hero h1 {
        font-size: 2rem;
      }

      .feature-card,
      .api-section {
        padding: 24px;
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
      <strong>Status:</strong> API v1.0 in Beta • Frontend in Development • Launch Q4 2024
    </p>
  </section>
</div>

<footer class="footer">
  <div class="container">
    <p>&copy; 2024 ICP Script Marketplace. Built with ❤️ for the Internet Computer community.</p>
    <p style="font-size: 0.9rem; margin-top: 10px;">
      Powered by <strong>Appwrite</strong> • Deployed on <strong>Internet Computer</strong>
    </p>
  </div>
</footer>
