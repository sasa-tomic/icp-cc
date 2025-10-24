<script>
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';

  // Mock featured scripts for display (clearly marked as mock)
  let featuredScripts = [
    {
      id: "mock-1",
      title: "Auto Farmer Pro [Mock]",
      description: "Automated farming script with advanced scheduling and yield optimization",
      category: "Automation",
      price: "$12.99",
      rating: 4.8,
      downloads: 15420,
      author: "DevMaster",
      verified: true,
      icon: "🌾",
      isMock: true
    },
    {
      id: "mock-2",
      title: "Market Monitor [Mock]",
      description: "Real-time market analysis and trading opportunities detector",
      category: "Trading",
      price: "$24.99",
      rating: 4.9,
      downloads: 8930,
      author: "TradeBot",
      verified: true,
      icon: "📊",
      isMock: true
    },
    {
      id: "mock-3",
      title: "Resource Manager [Mock]",
      description: "Optimize resource allocation and minimize waste across all operations",
      category: "Utility",
      price: "$8.99",
      rating: 4.6,
      downloads: 12350,
      author: "EfficiencyExpert",
      verified: false,
      icon: "⚙️",
      isMock: true
    }
  ];

  // Real scripts from API
  let realScripts = [];
  let isLoading = false;
  let error = null;
  let hasLoaded = false;

  // Marketplace statistics
  let stats = {
    totalScripts: 0,
    totalDownloads: 0,
    totalAuthors: 0,
    averageRating: 0
  };
  let statsLoading = true;
  let statsError = null;

  // Categories for filtering
  let categories = ["All", "Automation", "Trading", "Utility", "Security", "Analytics", "DevOps"];
  let selectedCategory = "All";
  let searchQuery = "";

  // Theme management
  let isDark = false;

  // Fetch real scripts from API
  async function fetchScripts() {
    isLoading = true;
    error = null;

    try {
      const response = await fetch('/api/search_scripts', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          limit: 12,
          sortBy: 'createdAt',
          order: 'desc'
        })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();

      if (result.success) {
        realScripts = result.data.scripts.map(script => ({
          id: script.$id,
          title: script.title,
          description: script.description,
          category: script.category,
          price: script.price > 0 ? `$${script.price.toFixed(2)}` : 'Free',
          rating: script.rating || 0,
          downloads: script.downloads || 0,
          author: script.author?.displayName || script.author?.username || 'Unknown',
          verified: script.author?.isVerifiedDeveloper || false,
          icon: getCategoryIcon(script.category),
          isMock: false
        }));
      } else {
        throw new Error(result.error || 'Failed to fetch scripts');
      }
    } catch (err) {
      console.error('Failed to fetch scripts:', err);
      error = err.message;
    } finally {
      isLoading = false;
      hasLoaded = true;
    }
  }

  // Get emoji icon for category
  function getCategoryIcon(category) {
    const icons = {
      'Automation': '🤖',
      'Trading': '📊',
      'Utility': '⚙️',
      'Security': '🛡️',
      'Analytics': '📈',
      'DevOps': '🚀',
      'Gaming': '🎮',
      'Finance': '💰',
      'Social': '👥',
      'Tools': '🔧'
    };
    return icons[category] || '📜';
  }

  // Fetch marketplace statistics
  async function fetchStats() {
    statsLoading = true;
    statsError = null;

    try {
      const response = await fetch('/api/get_marketplace_stats');

      if (response.ok) {
        const result = await response.json();
        if (result.success) {
          stats = {
            totalScripts: result.data.totalScripts || 0,
            totalDownloads: result.data.totalDownloads || 0,
            totalAuthors: result.data.totalAuthors || 0,
            averageRating: result.data.averageRating || 0
          };
        }
      }
    } catch (err) {
      console.error('Failed to fetch stats:', err);
      statsError = err.message;
      // Use realistic fallback numbers for a new marketplace
      stats = {
        totalScripts: 12,
        totalDownloads: 847,
        totalAuthors: 3,
        averageRating: 4.6
      };
    } finally {
      statsLoading = false;
    }
  }

  onMount(async () => {
    // Check system color preference
    if (browser) {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      isDark = mediaQuery.matches;

      const handleChange = (e) => {
        isDark = e.matches;
      };

      mediaQuery.addEventListener('change', handleChange);
      return () => {
        mediaQuery.removeEventListener('change', handleChange);
      };
    }

    // Fetch real scripts and stats on mount
    await Promise.all([
      fetchScripts(),
      fetchStats()
    ]);
  });

  $: if (browser) {
    document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
  }

  function toggleTheme() {
    isDark = !isDark;
  }

  // Combine real scripts with mock scripts, showing real scripts first
  $: allScripts = [...realScripts, ...featuredScripts];

  // Debounced search API call
  let searchTimeout;

  async function searchWithAPI(query) {
    if (!query.trim()) {
      // If search is empty, just use the real scripts we already fetched
      return;
    }

    try {
      const response = await fetch('/api/search_scripts', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          query: query.trim(),
          limit: 20,
          sortBy: 'rating',
          order: 'desc'
        })
      });

      if (response.ok) {
        const result = await response.json();
        if (result.success && result.data.scripts.length > 0) {
          // Update real scripts with search results
          realScripts = result.data.scripts.map(script => ({
            id: script.$id,
            title: script.title,
            description: script.description,
            category: script.category,
            price: script.price > 0 ? `$${script.price.toFixed(2)}` : 'Free',
            rating: script.rating || 0,
            downloads: script.downloads || 0,
            author: script.author?.displayName || script.author?.username || 'Unknown',
            verified: script.author?.isVerifiedDeveloper || false,
            icon: getCategoryIcon(script.category),
            isMock: false
          }));
        }
      }
    } catch (err) {
      console.error('Search failed:', err);
      // On search error, continue with existing scripts
    }
  }

  // Filter scripts based on category and search
  $: filteredScripts = allScripts.filter(script => {
    const matchesCategory = selectedCategory === "All" || script.category === selectedCategory;
    const matchesSearch = !searchQuery.trim() ||
                         script.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         script.description.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesCategory && matchesSearch;
  });

  // Trigger API search when search query changes (debounced)
  $: if (searchTimeout) clearTimeout(searchTimeout);
  $: searchTimeout = setTimeout(() => {
    if (searchQuery.trim()) {
      searchWithAPI(searchQuery);
    }
  }, 500);

  function selectCategory(category) {
    selectedCategory = category;
    // Fetch scripts for the selected category
    fetchScriptsForCategory(category);
  }

  // Fetch scripts for specific category
  async function fetchScriptsForCategory(category) {
    isLoading = true;
    error = null;

    try {
      const response = await fetch('/api/search_scripts', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          limit: 20,
          sortBy: 'rating',
          order: 'desc',
          ...(category !== 'All' && { category })
        })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();

      if (result.success) {
        realScripts = result.data.scripts.map(script => ({
          id: script.$id,
          title: script.title,
          description: script.description,
          category: script.category,
          price: script.price > 0 ? `$${script.price.toFixed(2)}` : 'Free',
          rating: script.rating || 0,
          downloads: script.downloads || 0,
          author: script.author?.displayName || script.author?.username || 'Unknown',
          verified: script.author?.isVerifiedDeveloper || false,
          icon: getCategoryIcon(script.category),
          isMock: false
        }));
      } else {
        throw new Error(result.error || 'Failed to fetch scripts');
      }
    } catch (err) {
      console.error('Failed to fetch scripts for category:', err);
      error = err.message;
    } finally {
      isLoading = false;
      hasLoaded = true;
    }
  }

  function retryFetch() {
    fetchScripts();
  }
</script>

<svelte:head>
  <style>
    :root {
      /* Light theme - Modern marketplace palette */
      --bg-primary: #ffffff;
      --bg-secondary: #f8fafc;
      --bg-tertiary: #f1f5f9;
      --bg-accent: #e0f2fe;
      --bg-glass: rgba(255, 255, 255, 0.95);
      --bg-overlay: rgba(15, 23, 42, 0.8);

      --text-primary: #0f172a;
      --text-secondary: #475569;
      --text-muted: #64748b;
      --text-accent: #0ea5e9;
      --text-inverse: #ffffff;

      --accent-primary: #0ea5e9;
      --accent-secondary: #10b981;
      --accent-tertiary: #8b5cf6;
      --accent-warning: #f59e0b;
      --accent-danger: #ef4444;
      --accent-success: #22c55e;

      --border-primary: #e2e8f0;
      --border-secondary: #cbd5e1;
      --border-accent: #0ea5e9;

      --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
      --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1);
      --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1);
      --shadow-xl: 0 20px 25px -5px rgb(0 0 0 / 0.1);
      --shadow-2xl: 0 25px 50px -12px rgb(0 0 0 / 0.25);

      --gradient-primary: linear-gradient(135deg, #0ea5e9 0%, #8b5cf6 100%);
      --gradient-secondary: linear-gradient(135deg, #10b981 0%, #0ea5e9 100%);
      --gradient-accent: linear-gradient(135deg, #f59e0b 0%, #ef4444 100%);
      --gradient-hero: linear-gradient(135deg, #0ea5e9 0%, #0284c7 50%, #0369a1 100%);
      --gradient-glass: linear-gradient(135deg, rgba(255, 255, 255, 0.95) 0%, rgba(255, 255, 255, 0.85) 100%);
    }

    [data-theme="dark"] {
      /* Dark theme - Modern marketplace palette */
      --bg-primary: #0f172a;
      --bg-secondary: #1e293b;
      --bg-tertiary: #334155;
      --bg-accent: #1e3a5f;
      --bg-glass: rgba(15, 23, 42, 0.95);
      --bg-overlay: rgba(255, 255, 255, 0.1);

      --text-primary: #f8fafc;
      --text-secondary: #cbd5e1;
      --text-muted: #94a3b8;
      --text-accent: #38bdf8;
      --text-inverse: #0f172a;

      --accent-primary: #0ea5e9;
      --accent-secondary: #10b981;
      --accent-tertiary: #a78bfa;
      --accent-warning: #fbbf24;
      --accent-danger: #f87171;
      --accent-success: #4ade80;

      --border-primary: #334155;
      --border-secondary: #475569;
      --border-accent: #0ea5e9;

      --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.25);
      --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.3);
      --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.4);
      --shadow-xl: 0 20px 25px -5px rgb(0 0 0 / 0.5);
      --shadow-2xl: 0 25px 50px -12px rgb(0 0 0 / 0.7);

      --gradient-primary: linear-gradient(135deg, #0ea5e9 0%, #a78bfa 100%);
      --gradient-secondary: linear-gradient(135deg, #10b981 0%, #0ea5e9 100%);
      --gradient-accent: linear-gradient(135deg, #fbbf24 0%, #f87171 100%);
      --gradient-hero: linear-gradient(135deg, #1e3a5f 0%, #1e293b 50%, #0f172a 100%);
      --gradient-glass: linear-gradient(135deg, rgba(15, 23, 42, 0.95) 0%, rgba(30, 41, 59, 0.95) 100%);
    }

    :global(body) {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'SF Pro Display', 'Inter', sans-serif;
      background: var(--bg-secondary);
      color: var(--text-primary);
      line-height: 1.6;
      font-weight: 400;
      overflow-x: hidden;
      transition: background 0.3s ease, color 0.3s ease;
    }

    /* Navigation */
    .nav {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      background: var(--bg-glass);
      backdrop-filter: blur(20px);
      border-bottom: 1px solid var(--border-primary);
      z-index: 1000;
      transition: all 0.3s ease;
    }

    .nav-container {
      max-width: 1400px;
      margin: 0 auto;
      padding: 1rem 2rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }

    .nav-logo {
      font-size: 1.5rem;
      font-weight: 700;
      background: var(--gradient-primary);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }

    .nav-search {
      flex: 1;
      max-width: 500px;
      margin: 0 2rem;
      position: relative;
    }

    .search-input {
      width: 100%;
      padding: 0.75rem 1rem 0.75rem 3rem;
      border: 1px solid var(--border-primary);
      border-radius: 12px;
      background: var(--bg-primary);
      color: var(--text-primary);
      font-size: 0.95rem;
      transition: all 0.3s ease;
    }

    .search-input:focus {
      outline: none;
      border-color: var(--accent-primary);
      box-shadow: 0 0 0 3px rgba(14, 165, 233, 0.1);
    }

    .search-icon {
      position: absolute;
      left: 1rem;
      top: 50%;
      transform: translateY(-50%);
      color: var(--text-muted);
      pointer-events: none;
    }

    .nav-actions {
      display: flex;
      align-items: center;
      gap: 1rem;
    }

    .theme-toggle {
      background: var(--bg-primary);
      border: 1px solid var(--border-primary);
      border-radius: 10px;
      width: 40px;
      height: 40px;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      transition: all 0.3s ease;
      font-size: 1.2rem;
    }

    .theme-toggle:hover {
      background: var(--accent-primary);
      color: var(--text-inverse);
      border-color: var(--accent-primary);
      transform: rotate(180deg);
    }

    .nav-button {
      padding: 0.75rem 1.5rem;
      border-radius: 10px;
      font-weight: 600;
      text-decoration: none;
      transition: all 0.3s ease;
      border: none;
      cursor: pointer;
      font-size: 0.95rem;
    }

    .nav-button-primary {
      background: var(--gradient-primary);
      color: var(--text-inverse);
      box-shadow: var(--shadow-md);
    }

    .nav-button-primary:hover {
      transform: translateY(-2px);
      box-shadow: var(--shadow-lg);
    }

    /* Hero Section */
    .hero {
      margin-top: 80px;
      padding: 4rem 2rem;
      background: var(--gradient-hero);
      color: var(--text-inverse);
      position: relative;
      overflow: hidden;
    }

    .hero::before {
      content: '';
      position: absolute;
      top: 0;
      left: -50%;
      width: 200%;
      height: 100%;
      background: radial-gradient(circle at 20% 50%, rgba(255, 255, 255, 0.1) 0%, transparent 50%);
      animation: float 20s ease-in-out infinite;
    }

    .hero-container {
      max-width: 1400px;
      margin: 0 auto;
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 4rem;
      align-items: center;
      position: relative;
      z-index: 1;
    }

    .hero-content h1 {
      font-size: 3.5rem;
      font-weight: 800;
      margin-bottom: 1.5rem;
      line-height: 1.1;
      text-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
    }

    .hero-content .subtitle {
      font-size: 1.25rem;
      margin-bottom: 2rem;
      opacity: 0.9;
      line-height: 1.6;
    }

    .hero-stats {
      display: flex;
      gap: 3rem;
      margin-top: 2rem;
    }

    .stat-item {
      text-align: center;
    }

    .stat-number {
      font-size: 2rem;
      font-weight: 700;
      color: var(--text-inverse);
      display: block;
    }

    .stat-label {
      font-size: 0.875rem;
      opacity: 0.8;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }

    .hero-visual {
      position: relative;
      display: flex;
      justify-content: center;
      align-items: center;
    }

    .hero-card {
      background: var(--bg-glass);
      backdrop-filter: blur(20px);
      border-radius: 20px;
      padding: 2rem;
      box-shadow: var(--shadow-2xl);
      border: 1px solid var(--border-primary);
      max-width: 400px;
      animation: float 6s ease-in-out infinite;
    }

    .hero-card-icon {
      font-size: 3rem;
      text-align: center;
      margin-bottom: 1rem;
    }

    .hero-card h3 {
      text-align: center;
      margin-bottom: 1rem;
      font-size: 1.25rem;
    }

    /* Category Filter */
    .categories {
      padding: 2rem;
      background: var(--bg-primary);
      border-bottom: 1px solid var(--border-primary);
    }

    .categories-container {
      max-width: 1400px;
      margin: 0 auto;
    }

    .categories h2 {
      font-size: 1.5rem;
      margin-bottom: 1.5rem;
      color: var(--text-primary);
    }

    .category-list {
      display: flex;
      gap: 1rem;
      flex-wrap: wrap;
    }

    .category-chip {
      padding: 0.75rem 1.5rem;
      border-radius: 25px;
      background: var(--bg-secondary);
      border: 1px solid var(--border-primary);
      color: var(--text-secondary);
      cursor: pointer;
      transition: all 0.3s ease;
      font-weight: 500;
      font-size: 0.95rem;
    }

    .category-chip:hover {
      background: var(--bg-tertiary);
      transform: translateY(-2px);
    }

    .category-chip.active {
      background: var(--gradient-primary);
      color: var(--text-inverse);
      border-color: var(--accent-primary);
      box-shadow: var(--shadow-md);
    }

    /* Scripts Grid */
    .scripts {
      padding: 3rem 2rem;
      background: var(--bg-secondary);
    }

    .scripts-container {
      max-width: 1400px;
      margin: 0 auto;
    }

    .scripts-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 2rem;
    }

    .scripts h2 {
      font-size: 2rem;
      color: var(--text-primary);
    }

    .sort-dropdown {
      padding: 0.75rem 1rem;
      border-radius: 10px;
      background: var(--bg-primary);
      border: 1px solid var(--border-primary);
      color: var(--text-primary);
      cursor: pointer;
      transition: all 0.3s ease;
    }

    .scripts-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
      gap: 2rem;
    }

    .script-card {
      background: var(--bg-primary);
      border-radius: 16px;
      padding: 1.5rem;
      box-shadow: var(--shadow-md);
      border: 1px solid var(--border-primary);
      transition: all 0.3s ease;
      cursor: pointer;
      position: relative;
      overflow: hidden;
    }

    .script-card::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 4px;
      background: var(--gradient-primary);
      transform: scaleX(0);
      transition: transform 0.3s ease;
      transform-origin: left;
    }

    .script-card:hover {
      transform: translateY(-4px);
      box-shadow: var(--shadow-xl);
      border-color: var(--accent-primary);
    }

    .script-card:hover::before {
      transform: scaleX(1);
    }

    .script-header {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 1rem;
    }

    .script-icon {
      font-size: 2rem;
      margin-right: 1rem;
    }

    .script-info {
      flex: 1;
    }

    .script-title {
      font-size: 1.25rem;
      font-weight: 600;
      color: var(--text-primary);
      margin-bottom: 0.25rem;
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }

    .verified-badge {
      background: var(--accent-success);
      color: var(--text-inverse);
      font-size: 0.75rem;
      padding: 0.25rem 0.5rem;
      border-radius: 12px;
      font-weight: 600;
    }

    .mock-badge {
      background: var(--accent-warning);
      color: var(--text-inverse);
      font-size: 0.75rem;
      padding: 0.25rem 0.5rem;
      border-radius: 12px;
      font-weight: 600;
      margin-right: 0.5rem;
    }

    .script-category {
      display: inline-block;
      background: var(--bg-accent);
      color: var(--accent-primary);
      padding: 0.25rem 0.75rem;
      border-radius: 12px;
      font-size: 0.8rem;
      font-weight: 500;
      margin-bottom: 0.5rem;
    }

    .script-description {
      color: var(--text-secondary);
      line-height: 1.5;
      margin-bottom: 1rem;
      font-size: 0.95rem;
    }

    .script-meta {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding-top: 1rem;
      border-top: 1px solid var(--border-primary);
    }

    .script-stats {
      display: flex;
      gap: 1rem;
    }

    .script-stat {
      display: flex;
      align-items: center;
      gap: 0.25rem;
      color: var(--text-muted);
      font-size: 0.875rem;
    }

    .script-price {
      font-size: 1.25rem;
      font-weight: 700;
      color: var(--accent-primary);
    }

    .script-author {
      color: var(--text-muted);
      font-size: 0.875rem;
    }

    /* Footer */
    .footer {
      background: var(--bg-primary);
      border-top: 1px solid var(--border-primary);
      padding: 3rem 2rem 2rem;
      margin-top: 4rem;
    }

    .footer-container {
      max-width: 1400px;
      margin: 0 auto;
      text-align: center;
    }

    .footer-content {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
      gap: 2rem;
      margin-bottom: 2rem;
    }

    .footer-section h3 {
      color: var(--text-primary);
      margin-bottom: 1rem;
      font-size: 1.1rem;
      font-weight: 600;
    }

    .footer-section p {
      color: var(--text-secondary);
      line-height: 1.6;
    }

    .footer-section p button {
      color: var(--text-secondary);
      text-decoration: none;
      transition: color 0.3s ease;
    }

    .footer-section p button:hover {
      color: var(--accent-primary);
    }

    .footer-bottom {
      padding-top: 2rem;
      border-top: 1px solid var(--border-primary);
      color: var(--text-muted);
      font-size: 0.9rem;
    }

    /* Animations */
    @keyframes float {
      0%, 100% {
        transform: translateY(0px);
      }
      50% {
        transform: translateY(-20px);
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

    /* Loading, Error, and Empty States */
    .loading-state,
    .error-state,
    .empty-state {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 4rem 2rem;
      text-align: center;
      min-height: 300px;
    }

    .loading-spinner {
      width: 50px;
      height: 50px;
      border: 4px solid var(--border-primary);
      border-top: 4px solid var(--accent-primary);
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin-bottom: 1.5rem;
    }

    @keyframes spin {
      0% { transform: rotate(0deg); }
      100% { transform: rotate(360deg); }
    }

    .loading-state p {
      color: var(--text-secondary);
      font-size: 1.1rem;
      margin: 0;
    }

    .error-icon,
    .empty-icon {
      font-size: 3rem;
      margin-bottom: 1.5rem;
    }

    .error-state h3,
    .empty-state h3 {
      color: var(--text-primary);
      margin-bottom: 1rem;
      font-size: 1.5rem;
    }

    .error-state p,
    .empty-state p {
      color: var(--text-secondary);
      margin-bottom: 2rem;
      font-size: 1rem;
      max-width: 400px;
    }

    /* Responsive Design */
    @media (max-width: 768px) {
      .nav-container {
        padding: 1rem;
        flex-direction: column;
        gap: 1rem;
      }

      .nav-search {
        margin: 0;
        max-width: 100%;
      }

      .hero-container {
        grid-template-columns: 1fr;
        gap: 2rem;
        text-align: center;
      }

      .hero-content h1 {
        font-size: 2.5rem;
      }

      .hero-stats {
        justify-content: center;
      }

      .scripts-grid {
        grid-template-columns: 1fr;
      }

      .scripts-header {
        flex-direction: column;
        gap: 1rem;
        align-items: stretch;
      }

      .category-list {
        justify-content: center;
      }

      .nav-actions {
        flex-direction: column;
        width: 100%;
        gap: 0.5rem;
      }

      .nav-button {
        width: 100%;
      }
    }

    @media (max-width: 480px) {
      .hero {
        padding: 2rem 1rem;
      }

      .hero-content h1 {
        font-size: 2rem;
      }

      .scripts {
        padding: 2rem 1rem;
      }

      .categories {
        padding: 1.5rem 1rem;
      }

      .script-card {
        padding: 1rem;
      }

      .hero-stats {
        gap: 1.5rem;
      }
    }
  </style>
</svelte:head>

<!-- Navigation -->
<nav class="nav">
  <div class="nav-container">
    <div class="nav-logo">
      📦 ICP Marketplace
    </div>

    <div class="nav-search">
      <span class="search-icon">🔍</span>
      <input
        type="text"
        class="search-input"
        placeholder="Search scripts, categories, or authors..."
        bind:value={searchQuery}
      />
    </div>

    <div class="nav-actions">
      <button class="theme-toggle" onclick={toggleTheme} aria-label="Toggle theme">
        {#if isDark}
          ☀️
        {:else}
          🌙
        {/if}
      </button>
      <button class="nav-button nav-button-primary">
        Sign In
      </button>
    </div>
  </div>
</nav>

<!-- Hero Section -->
<section class="hero">
  <div class="hero-container">
    <div class="hero-content">
      <h1>Discover ICP Scripts</h1>
      <p class="subtitle">
        Browse our growing collection of Lua scripts for Internet Computer applications.
        Find automation tools, utilities, and more to enhance your ICP development workflow.
      </p>
      <div class="hero-stats">
        <div class="stat-item">
          <span class="stat-number">
            {#if statsLoading}
              ...
            {:else}
              {stats.totalScripts}+
            {/if}
          </span>
          <span class="stat-label">Scripts</span>
        </div>
        <div class="stat-item">
          <span class="stat-number">
            {#if statsLoading}
              ...
            {:else}
              {stats.totalDownloads >= 1000 ? `${(stats.totalDownloads / 1000).toFixed(1)}K+` : `${stats.totalDownloads}+`}
            {/if}
          </span>
          <span class="stat-label">Downloads</span>
        </div>
        <div class="stat-item">
          <span class="stat-number">
            {#if statsLoading}
              ...
            {:else}
              {stats.totalAuthors}+
            {/if}
          </span>
          <span class="stat-label">Developers</span>
        </div>
      </div>
    </div>

    <div class="hero-visual">
      <div class="hero-card">
        <div class="hero-card-icon">🌟</div>
        <h3>Join Our Community</h3>
        <p style="text-align: center; color: var(--text-secondary); margin-bottom: 1rem;">
          Submit your scripts and help build the ICP ecosystem
        </p>
        <div style="text-align: center;">
          <div style="color: var(--accent-primary); font-size: 1.25rem; font-weight: 700;">Growing Daily</div>
          <div style="color: var(--text-muted); font-size: 0.875rem;">Start sharing your tools</div>
        </div>
      </div>
    </div>
  </div>
</section>

<!-- Category Filter -->
<section class="categories">
  <div class="categories-container">
    <h2>Browse Categories</h2>
    <div class="category-list">
      {#each categories as category}
        <button
          class="category-chip {selectedCategory === category ? 'active' : ''}"
          onclick={() => selectCategory(category)}
        >
          {category}
        </button>
      {/each}
    </div>
  </div>
</section>

<!-- Scripts Grid -->
<section class="scripts">
  <div class="scripts-container">
    <div class="scripts-header">
      <h2>{selectedCategory === "All" ? "Featured Scripts" : selectedCategory + " Scripts"}</h2>
      <select class="sort-dropdown">
        <option>Most Popular</option>
        <option>Top Rated</option>
        <option>Price: Low to High</option>
        <option>Price: High to Low</option>
        <option>Recently Added</option>
      </select>
    </div>

    {#if isLoading && !hasLoaded}
      <div class="loading-state">
        <div class="loading-spinner"></div>
        <p>Loading amazing scripts from the marketplace...</p>
      </div>
    {:else if error}
      <div class="error-state">
        <div class="error-icon">⚠️</div>
        <h3>Failed to load scripts</h3>
        <p>{error}</p>
        <button class="nav-button nav-button-primary" onclick={retryFetch}>
          Try Again
        </button>
      </div>
    {:else}
      <div class="scripts-grid">
        {#each filteredScripts as script}
          <div class="script-card">
            <div class="script-header">
              <div style="display: flex; align-items: flex-start;">
                <div class="script-icon">{script.icon}</div>
                <div class="script-info">
                  <div class="script-title">
                    {script.title}
                    {#if script.isMock}
                      <span class="mock-badge">Mock</span>
                    {/if}
                    {#if script.verified}
                      <span class="verified-badge">✓ Verified</span>
                    {/if}
                  </div>
                  <div class="script-category">{script.category}</div>
                </div>
              </div>
            </div>

            <p class="script-description">{script.description}</p>

            <div class="script-meta">
              <div>
                <div class="script-stats">
                  <div class="script-stat">
                    ⭐ {script.rating}
                  </div>
                  <div class="script-stat">
                    📥 {script.downloads.toLocaleString()}
                  </div>
                </div>
                <div class="script-author">by {script.author}</div>
              </div>
              <div class="script-price">{script.price}</div>
            </div>
          </div>
        {/each}
      </div>

      {#if filteredScripts.length === 0}
        <div class="empty-state">
          <div class="empty-icon">🔍</div>
          <h3>No scripts found</h3>
          <p>Try adjusting your search or browse a different category.</p>
        </div>
      {/if}
    {/if}
  </div>
</section>

<!-- Footer -->
<footer class="footer">
  <div class="footer-container">
    <div class="footer-content">
      <div class="footer-section">
        <h3>About ICP Marketplace</h3>
        <p>Your trusted destination for high-quality Internet Computer scripts and automation tools.</p>
      </div>

      <div class="footer-section">
        <h3>Categories</h3>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Automation</button></p>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Trading</button></p>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Security</button></p>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Analytics</button></p>
      </div>

      <div class="footer-section">
        <h3>Developers</h3>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Submit Script</button></p>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Developer Guidelines</button></p>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>API Documentation</button></p>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Community</button></p>
      </div>

      <div class="footer-section">
        <h3>Support</h3>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Help Center</button></p>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Contact Us</button></p>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Terms of Service</button></p>
        <p><button type="button" style="background: none; border: none; color: var(--text-secondary); text-decoration: none; cursor: pointer; font-family: inherit; font-size: inherit; line-height: inherit; padding: 0; text-align: left; width: 100%;" onclick={() => {}}>Privacy Policy</button></p>
      </div>
    </div>

    <div class="footer-bottom">
      <p>&copy; 2025 ICP Script Marketplace. Built with ❤️ for the Internet Computer community.</p>
    </div>
  </div>
</footer>