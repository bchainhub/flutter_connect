import 'dart:convert';

import 'providers.dart';

/// Builds a document-start provider bridge for native WebViews.
///
/// The host must validate [documentProperty] against the main document before
/// handling messages, revoke permissions on navigation, and deliver replies to
/// [replyProperty]. Discovery alone never authorizes wallet operations.
class WebViewProviders {
  static const documentProperty = '__connectProviderDocument';
  static const replyProperty = '__connectProviderReply';

  static String script({required ProviderInfo info, required String channel}) {
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(channel)) {
      throw ArgumentError.value(channel, 'channel', 'Invalid bridge channel');
    }
    return _script
        .replaceAll('__CHANNEL__', jsonEncode(channel))
        .replaceAll(
          '__INFO__',
          jsonEncode(info.toJson()).replaceAll('<', r'\u003c'),
        );
  }
}

const _script = r'''
(() => {
	if (window !== window.top || window.__connectProviderInstalled) return;
	if (location.protocol !== 'https:' && !(location.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(location.hostname))) return;
	Object.defineProperty(window, '__connectProviderInstalled', {value: true});
	const random = () => {
		const bytes = crypto.getRandomValues(new Uint8Array(16));
		bytes[6] = (bytes[6] & 15) | 64;
		bytes[8] = (bytes[8] & 63) | 128;
		const h = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
		return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
	};
	const documentId = random();
	Object.defineProperty(window, '__connectProviderDocument', {value: documentId});
	const pending = new Map();
	const listeners = new Map();
	window.__connectProviderReply = reply => {
		const entry = pending.get(String(reply.id));
		if (!entry) return;
		pending.delete(String(reply.id));
		clearTimeout(entry.timeout);
		if (reply.ok) {
			if (entry.method === 'xcb_requestAccounts' || entry.method === 'wallet.connect') {
				for (const fn of listeners.get('accountsChanged') || []) {
					try { fn(reply.result); } catch (_) {}
				}
			}
			entry.resolve(reply.result);
		} else {
			const error = new Error(reply.error?.message || 'Wallet request failed');
			error.code = reply.error?.code ?? -32603;
			entry.reject(error);
		}
	};
  // Browser detector adapted from device-sherlock 0.2.1 (CORE License).
  // Keep this local to the MiniApp sandbox: the npm package cannot run in
  // Flutter's native isolate, while navigator.userAgent belongs to this view.
  const detectDevice = (userAgent) => {
    const ua = String(userAgent || '');
    if (!ua) return Object.freeze({userAgent: null, isUnknown: true});
    const mobilePattern = /(android|bb\d+|meego).+mobile|avantgo|bada\/|blackberry|blazer|compal|elaine|fban|fbav|fennec|hiptop|iemobile|ip(hone|od)|instagram|iris|kindle|lge |maemo|midp|mmp|mobile.+firefox|netfront|opera m(ob|in)i|palm( os)?|phone|p(ixi|re)\/|plucker|pocket|psp|series(4|6)0|symbian|treo|up\.(browser|link)|vodafone|wap|windows ce|xda|xiino/i;
    const tabletPattern = /ipad|playbook|silk|tablet|kindle|android(?!.*mobile)/i;
    const mobile = mobilePattern.test(ua);
    const tablet = !mobile && tabletPattern.test(ua);
    const browser = /SamsungBrowser/i.test(ua) ? 'Samsung'
      : /edg([ea]|ios|)\//i.test(ua) ? 'Edge'
      : /firefox|iceweasel|fxios/i.test(ua) ? 'Firefox'
      : /chrome|crios|crmo/i.test(ua) ? 'Chrome'
      : /safari|applewebkit/i.test(ua) ? 'Safari'
      : '';
    const ios = /iPad|iPhone|iPod/.test(ua);
    const macOS = /Mac OS X/.test(ua);
    return Object.freeze({
      userAgent: ua,
      isUnknown: false,
      isMobile: mobile,
      isMobileOrTablet: mobile || tablet,
      isTablet: tablet,
      isDesktop: !mobile && !tablet,
      isIos: ios,
      isAndroid: /android/i.test(ua),
      isWindows: /Windows/.test(ua),
      isMacOS: macOS,
      isLinux: /Linux/.test(ua),
      isApple: macOS || ios,
      isDesktopOrTablet: !mobile,
      isSafari: browser === 'Safari',
      isFirefox: browser === 'Firefox',
      isEdge: browser === 'Edge',
      isChrome: browser === 'Chrome',
      isSamsung: browser === 'Samsung',
      browser
    });
  };
  const deviceSherlock = detectDevice(
    typeof navigator === 'undefined' ? '' : navigator.userAgent
  );

	const provider = Object.freeze({
		request(args) {
			if (!args || typeof args.method !== 'string' || !args.method ||
				(args.params != null && typeof args.params !== 'object')) {
				return Promise.reject(Object.assign(new Error('Invalid request'), {code: -32602}));
			}
			if (args.method === 'device.info') return Promise.resolve(deviceSherlock);
			return new Promise((resolve, reject) => {
				const id = random();
				const timeout = setTimeout(() => {
					pending.delete(id);
					reject(Object.assign(new Error('Request timed out'), {code: -32000}));
				}, 300000);
				pending.set(id, {resolve, reject, timeout, method: args.method});
				try {
					window[__CHANNEL__].postMessage(JSON.stringify({id, documentId, method: args.method, params: args.params ?? {}}));
				} catch (error) {
					clearTimeout(timeout); pending.delete(id); reject(error);
				}
			});
		},
		on(event, fn) {
			if (typeof fn !== 'function') throw new TypeError('Listener must be a function');
			if (!listeners.has(event)) listeners.set(event, new Set());
			listeners.get(event).add(fn);
			return provider;
		},
		removeListener(event, fn) { listeners.get(event)?.delete(fn); return provider; }
	});
	const info = Object.freeze({...__INFO__, uuid: random()});
	const detail = Object.freeze({info, provider});
	const announce = () => window.dispatchEvent(new CustomEvent('cip6963:announceProvider', {detail}));
	window.addEventListener('cip6963:requestProvider', announce);
	if (!('core' in window)) Object.defineProperty(window, 'core', {value: provider, enumerable: true});
	const connect = Object.freeze({
		request(args) {
			if (args?.blockchain != null && args.blockchain !== 'core') {
				return Promise.reject(Object.assign(new Error('Unsupported blockchain'), {code: 4200}));
			}
			return provider.request(args);
		}
	});
	if (!('connect' in window)) Object.defineProperty(window, 'connect', {value: connect, enumerable: true});
	if (typeof document !== 'undefined') document.addEventListener('click', event => {
		const anchor = event.target?.closest?.('a[href]');
		const href = anchor?.getAttribute('href')?.trim();
		if (!href || !/^payto:/i.test(href)) return;
		event.preventDefault();
		event.stopImmediatePropagation();
		provider.request({method: 'wallet_requestPayment', params: {uri: href}}).catch(error => {
			window.dispatchEvent(new CustomEvent('connect:paymentError', {detail: {code: error.code, message: error.message}}));
		});
	}, true);
	announce();
})();
''';
