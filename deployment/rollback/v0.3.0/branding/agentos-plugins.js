(function () {
  'use strict';

  var API_ROOT = '/api/agentos';
  var LOGO = '/assets/logo-mark.png?v0.3.14';
  var DEFAULT_AGENT_SPEC = 'agentos-agent-gpt-5-5';
  var BRAND_ASSET_NAME_PATTERN = /^(?:openai|anthropic|claude|google|gemini|azure|mistral|meta|deepseek|qwen|ollama|image_gen_oai|image_edit_oai)(?:[._-].*)?$/i;
  var state = {
    catalog: [],
    catalogLoaded: false,
    currentConversationId: null,
    selectedByConversation: Object.create(null),
    selectionRevision: Object.create(null),
    authHeader: '',
    menuOpen: false,
    host: null,
  };

  var originalFetch = window.fetch.bind(window);
  var originalXhrOpen = XMLHttpRequest.prototype.open;
  var originalXhrSend = XMLHttpRequest.prototype.send;
  var originalXhrSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
  var xhrMeta = new WeakMap();

  function captureAuthorization(headers) {
    if (!headers) return;
    if (typeof headers.get === 'function') {
      var header = headers.get('Authorization') || headers.get('authorization');
      if (header) state.authHeader = header;
      return;
    }
    Object.keys(headers).forEach(function (key) {
      if (key.toLowerCase() === 'authorization' && headers[key]) state.authHeader = headers[key];
    });
  }

  function requestHeaders() {
    var headers = { 'Content-Type': 'application/json' };
    if (state.authHeader) headers.Authorization = state.authHeader;
    return headers;
  }

  function pathOf(url) {
    try {
      return new URL(url, window.location.origin).pathname;
    } catch (_error) {
      return String(url || '').split('?')[0];
    }
  }

  function isAgentGenerationRequest(url, method) {
    var path = pathOf(url);
    return (
      String(method || 'GET').toUpperCase() === 'POST' &&
      (path === '/api/agents/chat' || /^\/api\/agents\/chat\/[^/]+$/.test(path)) &&
      !/^\/api\/agents\/chat\/(?:abort|active|status|stream)(?:\/|$)/.test(path)
    );
  }

  function selectedFor(conversationId) {
    var key = conversationId || state.currentConversationId || 'new';
    if (!Object.prototype.hasOwnProperty.call(state.selectedByConversation, key)) return null;
    return state.selectedByConversation[key];
  }

  function setLocalSelection(conversationId, selected) {
    state.selectionRevision[conversationId] = (state.selectionRevision[conversationId] || 0) + 1;
    state.selectedByConversation[conversationId] = (selected || []).slice();
  }

  function clearNewConversationDraft() {
    setLocalSelection('new', []);
    persistSelection('new', []);
  }

  function carryNewConversationDraft(conversationId) {
    if (!conversationId || conversationId === 'new') return false;
    var draft = selectedFor('new');
    if (!draft || !draft.length) return false;
    setLocalSelection(conversationId, draft);
    persistSelection(conversationId, draft);
    clearNewConversationDraft();
    return true;
  }

  function applyPluginSelection(body) {
    if (!body || typeof body !== 'object' || Array.isArray(body)) return body;
    var copy = Object.assign({}, body);
    var conversationId = copy.conversationId || state.currentConversationId || 'new';
    var selected = selectedFor(conversationId);
    delete copy.agentos_plugin_ids;
    if (selected) copy.agentos_plugin_ids = selected.slice();
    var isAgentSpec = typeof copy.spec === 'string' && /^agentos-agent-/.test(copy.spec);
    if (copy.endpoint === 'agents' || isAgentSpec) {
      if (isAgentSpec) copy.agent_id = 'ephemeral';
      if (copy.endpoint === 'agents') copy.endpointType = 'agents';
      var model = typeof copy.model === 'string' ? copy.model : '';
      var modelSpec = model
        ? 'agentos-agent-' + model.replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '')
        : DEFAULT_AGENT_SPEC;
      copy.spec = modelSpec || DEFAULT_AGENT_SPEC;
    }
    state.currentConversationId = conversationId;
    return copy;
  }

  function observeGenerationResponse(response, body) {
    try {
      response.clone().json().then(function (data) {
        var conversationId = data && (data.conversationId || data.conversation_id);
        if (!conversationId || !body) return;
        var previousId = body.conversationId || 'new';
        state.currentConversationId = conversationId;
        if (previousId === 'new' && carryNewConversationDraft(conversationId)) {
          render();
        }
      }).catch(function () {});
    } catch (_error) {}
  }

  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : input && input.url;
    var method = (init && init.method) || (input && input.method) || 'GET';
    captureAuthorization(init && init.headers);
    captureAuthorization(input && typeof input !== 'string' ? input.headers : null);
    var nextInit = init ? Object.assign({}, init) : {};
    var bodyObject = null;
    if (isAgentGenerationRequest(url, method) && typeof nextInit.body === 'string') {
      try {
        bodyObject = JSON.parse(nextInit.body);
        nextInit.body = JSON.stringify(applyPluginSelection(bodyObject));
      } catch (_error) {}
    }
    return originalFetch(input, nextInit).then(function (response) {
      if (bodyObject) observeGenerationResponse(response, bodyObject);
      return response;
    });
  };

  XMLHttpRequest.prototype.open = function (method, url) {
    xhrMeta.set(this, { method: method, url: url });
    return originalXhrOpen.apply(this, arguments);
  };

  XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
    if (String(name).toLowerCase() === 'authorization') state.authHeader = value;
    return originalXhrSetRequestHeader.apply(this, arguments);
  };

  XMLHttpRequest.prototype.send = function (body) {
    var meta = xhrMeta.get(this) || {};
    var bodyObject = null;
    if (isAgentGenerationRequest(meta.url, meta.method) && typeof body === 'string') {
      try {
        bodyObject = JSON.parse(body);
        body = JSON.stringify(applyPluginSelection(bodyObject));
      } catch (_error) {}
    }
    if (bodyObject) {
      this.addEventListener('load', function () {
        try {
          var data = JSON.parse(this.responseText || '{}');
          var conversationId = data && (data.conversationId || data.conversation_id);
          if (!conversationId) return;
          var previousId = bodyObject.conversationId || 'new';
          state.currentConversationId = conversationId;
          if (previousId === 'new' && carryNewConversationDraft(conversationId)) {
            render();
          }
        } catch (_error) {}
      });
    }
    return originalXhrSend.call(this, body);
  };

  function requestJson(path, options) {
    var opts = options || {};
    var headers = Object.assign({}, requestHeaders(), opts.headers || {});
    return originalFetch(API_ROOT + path, {
      method: opts.method || 'GET',
      headers: headers,
      credentials: 'same-origin',
      body: opts.body,
    }).then(function (response) {
      if (!response.ok) {
        return response.text().then(function (detail) {
          var message = 'AgentOS plugin request failed (' + response.status + ')';
          try {
            var payload = JSON.parse(detail);
            if (payload && payload.message) message += ': ' + payload.message;
          } catch (_error) {}
          var error = new Error(message);
          error.status = response.status;
          throw error;
        });
      }
      return response.json();
    });
  }

  function persistSelection(conversationId, selected, attempt) {
    if (!conversationId) return Promise.resolve();
    return requestJson('/selection', {
      method: 'PUT',
      body: JSON.stringify({ conversation_id: conversationId, selected_plugin_ids: selected }),
    }).catch(function (error) {
      if (error.status === 401 && (attempt || 0) < 4) {
        return new Promise(function (resolve) {
          window.setTimeout(resolve, 250 * ((attempt || 0) + 1));
        }).then(function () {
          return persistSelection(conversationId, selected, (attempt || 0) + 1);
        });
      }
      console.warn('[AgentOS] Unable to save plugin selection:', error.message);
    });
  }

  function loadSelection(conversationId, attempt) {
    if (!conversationId || Object.prototype.hasOwnProperty.call(state.selectedByConversation, conversationId)) {
      render();
      return Promise.resolve();
    }
    var revision = state.selectionRevision[conversationId] || 0;
    return requestJson('/selection?conversation_id=' + encodeURIComponent(conversationId))
      .then(function (data) {
        if ((state.selectionRevision[conversationId] || 0) !== revision) return;
        state.selectedByConversation[conversationId] = Array.isArray(data.selected_plugin_ids)
          ? data.selected_plugin_ids
          : [];
        render();
      })
      .catch(function (error) {
        if (error.status === 401 && (attempt || 0) < 4) {
          return new Promise(function (resolve) {
            window.setTimeout(resolve, 250 * ((attempt || 0) + 1));
          }).then(function () {
            return loadSelection(conversationId, (attempt || 0) + 1);
          });
        }
        console.warn('[AgentOS] Unable to load plugin selection:', error.message);
        delete state.selectedByConversation[conversationId];
      });
  }

  function loadCatalog(attempt) {
    if (state.catalogLoaded) return;
    return requestJson('/catalog')
      .then(function (data) {
        state.catalog = Array.isArray(data.plugins) ? data.plugins : [];
        state.catalogLoaded = true;
        render();
      })
      .catch(function (error) {
        if (error.status === 401 && (attempt || 0) < 4) {
          return new Promise(function (resolve) {
            window.setTimeout(resolve, 250 * ((attempt || 0) + 1));
          }).then(function () {
            return loadCatalog((attempt || 0) + 1);
          });
        }
        console.warn('[AgentOS] Unable to load plugin catalog:', error.message);
      });
  }

  function routeConversationId() {
    var path = window.location.pathname;
    var match = path.match(/\/(?:c|chat)\/([A-Za-z0-9_-]{8,128})/);
    return match ? match[1] : 'new';
  }

  function isWorkspacePage() {
    return !/^\/(?:login|register|forgot-password|reset-password|verify)(?:\/|$)/.test(window.location.pathname);
  }

  function syncRoute() {
    if (!isWorkspacePage()) {
      render();
      return;
    }
    var conversationId = routeConversationId();
    if (conversationId === state.currentConversationId) return;
    var previousConversationId = state.currentConversationId;
    state.currentConversationId = conversationId;
    if (conversationId === 'new') {
      clearNewConversationDraft();
      render();
      return;
    }
    loadSelection(conversationId);
    render();
  }

  function selectedPlugins() {
    var ids = selectedFor(state.currentConversationId || 'new') || [];
    return ids.map(function (id) {
      return state.catalog.find(function (plugin) { return plugin.id === id; });
    }).filter(Boolean);
  }

  function iconFor(plugin) {
    return plugin && typeof plugin.icon === 'string' && plugin.icon.indexOf('/assets/') === 0
      ? plugin.icon
      : LOGO;
  }

  function isBrandAssetSource(source) {
    if (!source || /^(?:data|blob):/i.test(source)) return false;
    try {
      var parsed = new URL(source, window.location.origin);
      if (parsed.origin !== window.location.origin || parsed.pathname.indexOf('/assets/') === -1) {
        return false;
      }
      var filename = parsed.pathname.slice(parsed.pathname.lastIndexOf('/') + 1);
      return BRAND_ASSET_NAME_PATTERN.test(filename);
    } catch (_error) {
      return false;
    }
  }

  function applyBrandIcons(root) {
    var scope = root && root.querySelectorAll ? root : document;
    scope.querySelectorAll('img').forEach(function (image) {
      var source = image.getAttribute('src') || '';
      if (image.dataset.agentosBrandIcon === 'true') return;
      if (isBrandAssetSource(source)) {
        image.src = LOGO;
        image.dataset.agentosBrandIcon = 'true';
      }
    });
  }

  function renderList(list, query) {
    if (!list) return;
    list.innerHTML = '';
    var normalizedQuery = String(query || '').trim().toLowerCase();
    var selected = selectedFor(state.currentConversationId || 'new') || [];
    var visible = state.catalog.filter(function (plugin) {
      return !normalizedQuery || (plugin.name + ' ' + plugin.description).toLowerCase().indexOf(normalizedQuery) !== -1;
    });
    if (!visible.length) {
      var empty = document.createElement('div');
      empty.className = 'agentos-plugin-empty';
      empty.textContent = state.catalogLoaded ? '没有匹配的插件' : '插件目录加载中...';
      list.appendChild(empty);
      return;
    }
    visible.forEach(function (plugin) {
      var row = document.createElement('div');
      row.className = 'agentos-plugin-row';
      var icon = document.createElement('img');
      icon.src = iconFor(plugin);
      icon.alt = '';
      var copy = document.createElement('div');
      copy.className = 'agentos-plugin-copy';
      var title = document.createElement('strong');
      title.textContent = plugin.name;
      var description = document.createElement('span');
      description.textContent = plugin.description;
      description.className = 'agentos-plugin-description';
      copy.appendChild(title);
      copy.appendChild(description);
      if (plugin.modelType && Array.isArray(plugin.models) && plugin.models.length) {
        var modelMeta = document.createElement('span');
        var defaultModel = plugin.defaultModel || plugin.models[0];
        modelMeta.className = 'agentos-plugin-meta';
        modelMeta.textContent = (plugin.modelType === 'image' ? '图片模型' : '可用模型') + ' · 默认 ' + defaultModel;
        modelMeta.title = plugin.models.join(', ');
        copy.appendChild(modelMeta);
      }
      var action = document.createElement('button');
      var isSelected = selected.indexOf(plugin.id) !== -1;
      action.type = 'button';
      action.className = isSelected ? 'agentos-plugin-action selected' : 'agentos-plugin-action';
      action.dataset.pluginId = plugin.id;
      action.dataset.action = isSelected ? 'remove' : 'add';
      action.textContent = isSelected ? '移除' : '添加';
      row.appendChild(icon);
      row.appendChild(copy);
      row.appendChild(action);
      list.appendChild(row);
    });
  }

  function render() {
    if (!isWorkspacePage()) {
      if (state.host) state.host.style.display = 'none';
      return;
    }
    applyBrandIcons(document);
    if (!state.host) {
      state.host = document.createElement('div');
      state.host.id = 'agentos-plugin-picker';
      document.body.appendChild(state.host);
    }
    state.host.style.display = '';
    var selected = selectedPlugins();
    state.host.innerHTML = '';
    var bar = document.createElement('div');
    bar.className = 'agentos-plugin-bar';
    var chips = document.createElement('div');
    chips.className = 'agentos-plugin-chips';
    selected.forEach(function (plugin) {
      var chip = document.createElement('span');
      chip.className = 'agentos-plugin-chip';
      chip.textContent = plugin.name;
      var remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'agentos-plugin-chip-remove';
      remove.title = '移除 ' + plugin.name;
      remove.setAttribute('aria-label', '移除 ' + plugin.name);
      remove.dataset.pluginId = plugin.id;
      remove.dataset.action = 'remove';
      remove.textContent = '×';
      chip.appendChild(remove);
      chips.appendChild(chip);
    });
    var button = document.createElement('button');
    button.type = 'button';
    button.className = state.menuOpen ? 'agentos-plugin-button open' : 'agentos-plugin-button';
    button.title = '选择公司 AI 能力（含 AI 生图）';
    button.innerHTML = '<img src="' + LOGO + '" alt="" /><span>AI 能力</span><span class="agentos-plugin-count">' + selected.length + '</span>';
    button.dataset.action = 'toggle';
    bar.appendChild(chips);
    bar.appendChild(button);
    state.host.appendChild(bar);

    var menu = document.createElement('div');
    menu.className = state.menuOpen ? 'agentos-plugin-menu open' : 'agentos-plugin-menu';
    var heading = document.createElement('div');
    heading.className = 'agentos-plugin-menu-heading';
    heading.innerHTML = '<strong>公司 AI 能力</strong><span>当前会话</span>';
    var search = document.createElement('input');
    search.type = 'search';
    search.className = 'agentos-plugin-search';
    search.placeholder = '搜索插件';
    search.setAttribute('aria-label', '搜索插件');
    var list = document.createElement('div');
    list.className = 'agentos-plugin-list';
    menu.appendChild(heading);
    menu.appendChild(search);
    menu.appendChild(list);
    state.host.appendChild(menu);
    renderList(list, '');
    search.addEventListener('input', function () { renderList(list, search.value); });
  }

  function updateSelection(action, pluginId) {
    var conversationId = state.currentConversationId || 'new';
    var current = (selectedFor(conversationId) || []).slice();
    var index = current.indexOf(pluginId);
    if (action === 'add' && index === -1) current.push(pluginId);
    if (action === 'remove' && index !== -1) current.splice(index, 1);
    setLocalSelection(conversationId, current);
    persistSelection(conversationId, current);
    render();
  }

  document.addEventListener('click', function (event) {
    var target = event.target.closest ? event.target.closest('[data-action]') : null;
    if (target && state.host && state.host.contains(target)) {
      var action = target.dataset.action;
      if (action === 'toggle') {
        state.menuOpen = !state.menuOpen;
        render();
      } else if (action === 'add' || action === 'remove') {
        updateSelection(action, target.dataset.pluginId);
      }
      return;
    }
    if (state.menuOpen && state.host && !state.host.contains(event.target)) {
      state.menuOpen = false;
      render();
    }
  });

  function boot() {
    applyBrandIcons(document);
    if (window.MutationObserver) {
      new MutationObserver(function (mutations) {
        mutations.forEach(function (mutation) {
          mutation.addedNodes.forEach(function (node) {
            if (node.nodeType === 1) applyBrandIcons(node);
          });
        });
      }).observe(document.body, { childList: true, subtree: true });
    }
    syncRoute();
    loadCatalog();
    render();
    window.setInterval(function () {
      syncRoute();
      if (!state.catalogLoaded) loadCatalog();
    }, 1500);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
