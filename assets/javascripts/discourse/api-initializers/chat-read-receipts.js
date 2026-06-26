import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";

export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  if (!siteSettings.chat_read_receipts_enabled) {
    return;
  }

  const chat = api.container.lookup("service:chat");
  const currentUser = api.getCurrentUser();

  if (!chat?.userCanChat || !currentUser) {
    return;
  }

  const state = {
    activeChannelId: null,
    inFlight: false,
    pendingRefresh: false,
    refreshScheduled: false,
    pollTimer: null,
    openReceipt: null,
  };

  function refreshIntervalMs() {
    return Number(siteSettings.chat_read_receipts_refresh_interval_seconds) * 1000;
  }

  function inlineAvatarCount() {
    const count = Number(siteSettings.chat_read_receipts_inline_avatar_count);

    if (Number.isInteger(count) && count > 0) {
      return count;
    }

    // 设置缺失或被错误配置时只影响行内展示，完整名单仍保留在展开面板里。
    return 5;
  }

  function visibleMessageContainers() {
    return Array.from(
      document.querySelectorAll(".chat-message-container[data-id]")
    ).filter((container) => Number.isInteger(Number(container.dataset.id)));
  }

  function currentChannelId() {
    const channelId = Number(chat.activeChannel?.id);
    return Number.isInteger(channelId) ? channelId : null;
  }

  function avatarUrl(user, size = 24) {
    const template = user?.avatar_template;
    if (!template) {
      return null;
    }

    return template.includes("{size}") ? template.replace("{size}", size) : template;
  }

  function displayName(user) {
    return user?.name || user?.username || "";
  }

  function formatReadTime(value) {
    if (!value) {
      return "已读";
    }

    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return "已读";
    }

    return new Intl.DateTimeFormat(undefined, {
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).format(date);
  }

  function sortedReceipts(receipts) {
    return [...receipts].sort((left, right) => {
      const leftTime = left.last_read_at ? new Date(left.last_read_at).getTime() : 0;
      const rightTime = right.last_read_at ? new Date(right.last_read_at).getTime() : 0;
      return rightTime - leftTime;
    });
  }

  function receiptSignature(receipts) {
    return receipts
      .map((receipt) => `${receipt.id}:${receipt.last_read_at || ""}`)
      .join("|");
  }

  function closeReceiptPanel() {
    if (!state.openReceipt) {
      return;
    }

    state.openReceipt.classList.remove("is-open");
    state.openReceipt
      .querySelector(".crr-read-receipt__trigger")
      ?.setAttribute("aria-expanded", "false");
    state.openReceipt.querySelector(".crr-read-receipt__panel")?.setAttribute("hidden", "");
    state.openReceipt = null;
  }

  function removeAllReceipts() {
    closeReceiptPanel();
    document.querySelectorAll(".crr-read-receipt").forEach((receipt) => receipt.remove());
  }

  function buildAvatar(receipt, className, size) {
    const src = avatarUrl(receipt, size);
    if (!src) {
      const fallback = document.createElement("span");
      fallback.className = `${className} ${className}-fallback`;
      fallback.textContent = displayName(receipt).charAt(0).toUpperCase();
      return fallback;
    }

    const avatar = document.createElement("img");
    avatar.className = className;
    avatar.src = src;
    avatar.alt = displayName(receipt);
    avatar.loading = "lazy";
    return avatar;
  }

  function buildReceiptElement(receipts) {
    const sorted = sortedReceipts(receipts);
    const wrapper = document.createElement("div");
    wrapper.className = "crr-read-receipt";
    wrapper.dataset.signature = receiptSignature(sorted);

    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "crr-read-receipt__trigger";
    trigger.setAttribute("aria-expanded", "false");
    trigger.setAttribute("aria-label", `${sorted.length} 位用户已读`);

    const avatars = document.createElement("span");
    avatars.className = "crr-read-receipt__avatars";
    const visibleAvatarCount = inlineAvatarCount();

    sorted.slice(0, visibleAvatarCount).forEach((receipt) => {
      avatars.appendChild(buildAvatar(receipt, "crr-read-receipt__avatar", 24));
    });

    const hiddenCount = sorted.length - visibleAvatarCount;
    if (hiddenCount > 0) {
      const overflow = document.createElement("span");
      overflow.className = "crr-read-receipt__overflow";
      overflow.textContent = `+${hiddenCount}`;
      avatars.appendChild(overflow);
    }

    trigger.appendChild(avatars);

    const panel = document.createElement("div");
    panel.className = "crr-read-receipt__panel";
    panel.hidden = true;

    const title = document.createElement("div");
    title.className = "crr-read-receipt__title";
    title.textContent = "已读用户";
    panel.appendChild(title);

    const list = document.createElement("div");
    list.className = "crr-read-receipt__list";
    sorted.forEach((receipt) => {
      const item = document.createElement("div");
      item.className = "crr-read-receipt__item";
      item.appendChild(buildAvatar(receipt, "crr-read-receipt__item-avatar", 40));

      const content = document.createElement("div");
      content.className = "crr-read-receipt__item-content";

      const name = document.createElement("span");
      name.className = "crr-read-receipt__item-name";
      name.textContent = displayName(receipt);

      const time = document.createElement("span");
      time.className = "crr-read-receipt__item-time";
      time.textContent = formatReadTime(receipt.last_read_at);

      content.appendChild(name);
      content.appendChild(time);
      item.appendChild(content);
      list.appendChild(item);
    });
    panel.appendChild(list);

    wrapper.appendChild(trigger);
    wrapper.appendChild(panel);
    return wrapper;
  }

  function renderReceipts(receiptsByMessageId) {
    const activeMessageIds = new Set();

    visibleMessageContainers().forEach((container) => {
      const messageId = container.dataset.id;
      activeMessageIds.add(messageId);

      const receipts = receiptsByMessageId[messageId] || [];
      const existing = container.querySelector(".crr-read-receipt");

      if (receipts.length === 0) {
        if (existing === state.openReceipt) {
          closeReceiptPanel();
        }
        existing?.remove();
        return;
      }

      const signature = receiptSignature(sortedReceipts(receipts));
      if (existing?.dataset.signature === signature) {
        return;
      }

      const nextReceipt = buildReceiptElement(receipts);
      if (existing) {
        if (existing === state.openReceipt) {
          closeReceiptPanel();
        }
        existing.replaceWith(nextReceipt);
      } else {
        container.appendChild(nextReceipt);
      }
    });

    document.querySelectorAll(".crr-read-receipt").forEach((receipt) => {
      const messageId = receipt.closest(".chat-message-container")?.dataset?.id;
      if (!messageId || !activeMessageIds.has(messageId)) {
        if (receipt === state.openReceipt) {
          closeReceiptPanel();
        }
        receipt.remove();
      }
    });
  }

  async function fetchReceipts(channelId, messageIds) {
    return ajax("/chat-read-receipts/receipts", {
      type: "POST",
      data: {
        channel_id: channelId,
        message_ids: messageIds,
      },
    });
  }

  async function refreshReceipts() {
    if (state.inFlight) {
      state.pendingRefresh = true;
      return;
    }

    const channelId = currentChannelId();
    const containers = visibleMessageContainers();

    if (!channelId || containers.length === 0) {
      state.activeChannelId = channelId;
      removeAllReceipts();
      return;
    }

    if (state.activeChannelId !== channelId) {
      state.activeChannelId = channelId;
      removeAllReceipts();
    }

    const messageIds = containers.map((container) => Number(container.dataset.id));
    state.inFlight = true;

    try {
      const response = await fetchReceipts(channelId, messageIds);
      if (!response?.receipts) {
        removeAllReceipts();
        // eslint-disable-next-line no-console
        console.warn("[chat-read-receipts] Read receipts API returned an invalid payload", response);
        return;
      }

      renderReceipts(response.receipts);
    } catch (error) {
      removeAllReceipts();
      // eslint-disable-next-line no-console
      console.warn("[chat-read-receipts] Failed to fetch chat read receipts", error);
    } finally {
      state.inFlight = false;

      if (state.pendingRefresh) {
        state.pendingRefresh = false;
        scheduleRefresh();
      }
    }
  }

  function scheduleRefresh() {
    if (state.refreshScheduled) {
      return;
    }

    state.refreshScheduled = true;
    Promise.resolve().then(() => {
      state.refreshScheduled = false;
      refreshReceipts();
    });
  }

  function onDocumentClick(event) {
    const trigger = event.target.closest(".crr-read-receipt__trigger");
    if (trigger) {
      event.preventDefault();

      const receipt = trigger.closest(".crr-read-receipt");
      const isOpen = receipt?.classList.contains("is-open");
      closeReceiptPanel();

      if (!isOpen && receipt) {
        receipt.classList.add("is-open");
        trigger.setAttribute("aria-expanded", "true");
        receipt.querySelector(".crr-read-receipt__panel")?.removeAttribute("hidden");
        state.openReceipt = receipt;
      }
      return;
    }

    if (!event.target.closest(".crr-read-receipt")) {
      closeReceiptPanel();
    }
  }

  function onDocumentKeydown(event) {
    if (event.key === "Escape") {
      closeReceiptPanel();
    }
  }

  api.decorateChatMessage(() => scheduleRefresh(), { id: "chat-read-receipts" });
  api.onPageChange(() => scheduleRefresh());

  document.addEventListener("click", onDocumentClick);
  document.addEventListener("keydown", onDocumentKeydown);

  // 该间隔来自站点设置，最小值为 1 秒，避免 0 或负数造成浏览器紧密轮询。
  state.pollTimer = setInterval(scheduleRefresh, refreshIntervalMs());

  scheduleRefresh();
});
