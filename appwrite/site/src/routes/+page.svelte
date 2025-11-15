<script>
  import { onMount } from 'svelte';

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

  onMount(() => {
    // Add smooth scroll behavior
    document.documentElement.style.scrollBehavior = 'smooth';
  });
</script>

<svelte:head>
  <style>
    :global(body) {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      color: #333;
    }

    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 0 20px;
    }

    .hero {
      text-align: center;
      padding: 80px 20px;
      color: white;
    }

    .hero h1 {
      font-size: 3.5rem;
      font-weight: 700;
      margin-bottom: 20px;
      text-shadow: 0 4px 6px rgba(0,0,0,0.1);
      animation: fadeInUp 0.8s ease-out;
    }

    .hero .subtitle {
      font-size: 1.3rem;
      margin-bottom: 40px;
      opacity: 0.9;
      max-width: 600px;
      margin-left: auto;
      margin-right: auto;
      animation: fadeInUp 0.8s ease-out 0.2s both;
    }

    .features {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 30px;
      margin-bottom: 80px;
      animation: fadeInUp 0.8s ease-out 0.4s both;
    }

    .feature-card {
      background: rgba(255, 255, 255, 0.95);
      backdrop-filter: blur(10px);
      border-radius: 16px;
      padding: 30px;
      box-shadow: 0 20px 40px rgba(0,0,0,0.1);
      transition: transform 0.3s ease, box-shadow 0.3s ease;
    }

    .feature-card:hover {
      transform: translateY(-5px);
      box-shadow: 0 30px 60px rgba(0,0,0,0.15);
    }

    .feature-card h3 {
      color: #667eea;
      margin-top: 0;
      margin-bottom: 15px;
      font-size: 1.5rem;
    }

    .feature-card p {
      line-height: 1.6;
      color: #666;
      margin-bottom: 20px;
    }

    .api-section {
      background: rgba(255, 255, 255, 0.98);
      border-radius: 20px;
      padding: 50px;
      margin-bottom: 80px;
      box-shadow: 0 25px 50px rgba(0,0,0,0.1);
      animation: fadeInUp 0.8s ease-out 0.6s both;
    }

    .api-section h2 {
      text-align: center;
      color: #333;
      margin-bottom: 50px;
      font-size: 2.5rem;
    }

    .endpoint-grid {
      display: grid;
      gap: 25px;
    }

    .endpoint-card {
      background: #f8f9ff;
      border-left: 4px solid #667eea;
      border-radius: 12px;
      padding: 25px;
      transition: all 0.3s ease;
    }

    .endpoint-card:hover {
      background: #f0f2ff;
      transform: translateX(5px);
    }

    .endpoint-header {
      display: flex;
      align-items: center;
      margin-bottom: 15px;
      flex-wrap: wrap;
      gap: 10px;
    }

    .method {
      background: #667eea;
      color: white;
      padding: 6px 12px;
      border-radius: 20px;
      font-size: 0.85rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .method.post { background: #48bb78; }
    .method.get { background: #4299e1; }

    .path {
      font-family: 'Monaco', 'Menlo', monospace;
      background: #2d3748;
      color: #68d391;
      padding: 8px 14px;
      border-radius: 8px;
      font-size: 0.9rem;
      font-weight: 500;
    }

    .endpoint-description {
      color: #555;
      line-height: 1.6;
      margin-bottom: 15px;
    }

    .parameters {
      margin-top: 15px;
    }

    .parameters h4 {
      color: #333;
      margin-bottom: 8px;
      font-size: 0.9rem;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .param-tags {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
    }

    .param-tag {
      background: #e2e8f0;
      color: #4a5568;
      padding: 4px 10px;
      border-radius: 12px;
      font-size: 0.8rem;
      font-family: 'Monaco', 'Menlo', monospace;
    }

    .coming-soon {
      text-align: center;
      padding: 60px 20px;
      color: white;
      animation: fadeInUp 0.8s ease-out 0.8s both;
    }

    .coming-soon h2 {
      font-size: 2.5rem;
      margin-bottom: 20px;
    }

    .coming-soon p {
      font-size: 1.2rem;
      opacity: 0.9;
      max-width: 600px;
      margin: 0 auto 30px;
    }

    .beta-badge {
      display: inline-block;
      background: #f6ad55;
      color: #744210;
      padding: 8px 16px;
      border-radius: 20px;
      font-size: 0.85rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-left: 10px;
    }

    .footer {
      text-align: center;
      padding: 40px 20px;
      color: rgba(255, 255, 255, 0.8);
      animation: fadeInUp 0.8s ease-out 1s both;
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
        font-size: 1.1rem;
      }

      .api-section {
        padding: 30px 20px;
      }

      .endpoint-header {
        flex-direction: column;
        align-items: flex-start;
      }

      .features {
        grid-template-columns: 1fr;
      }
    }
  </style>
</svelte:head>

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
