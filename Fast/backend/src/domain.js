export const ORDER_TRANSITIONS = Object.freeze({
  pending: ['accepted', 'cancelled'],
  accepted: ['preparing', 'cancelled'],
  preparing: ['ready', 'cancelled'],
  ready: ['assigned', 'cancelled'],
  assigned: ['picked_up', 'cancelled'],
  picked_up: ['on_the_way', 'cancelled'],
  on_the_way: ['delivered', 'cancelled'],
  delivered: [],
  cancelled: [],
});

export function canTransition(from, to) {
  return ORDER_TRANSITIONS[from]?.includes(to) ?? false;
}

export function haversineKm(aLat, aLng, bLat, bLng) {
  const values = [aLat, aLng, bLat, bLng].map(Number);
  if (values.some((value) => !Number.isFinite(value))) return null;
  const [lat1, lon1, lat2, lon2] = values;
  if (Math.abs(lat1) > 90 || Math.abs(lat2) > 90 || Math.abs(lon1) > 180 || Math.abs(lon2) > 180) return null;
  const rad = (degrees) => (degrees * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 6371.0088 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

export function calculateDeliveryFee(distanceKm, baseFee, perKmFee) {
  const base = Math.max(0, Math.trunc(Number(baseFee)));
  const rate = Math.max(0, Math.trunc(Number(perKmFee)));
  if (distanceKm === null || distanceKm === undefined || !Number.isFinite(Number(distanceKm))) return base;
  return base + Math.ceil(Math.max(0, Number(distanceKm))) * rate;
}
