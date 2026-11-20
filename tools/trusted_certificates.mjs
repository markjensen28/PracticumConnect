import tls from 'node:tls';

// Firebase Admin and Storage requests must also trust locally installed roots
// (for example, those used by a managed network). Keep the bundled and extra
// roots, and leave TLS certificate and hostname verification enabled.
if (typeof tls.getCACertificates === 'function' &&
    typeof tls.setDefaultCACertificates === 'function') {
  tls.setDefaultCACertificates([
    ...tls.getCACertificates('default'),
    ...tls.getCACertificates('system'),
  ]);
}
