// Minimal ambient types for the NAVER Maps JavaScript API v3 (loaded via a
// plain <script> tag, see lib/naverMapsLoader.ts) — just the surface this
// app actually uses (Map/Marker/InfoWindow display, plus the Geocoder
// submodule), not a full port of Naver's own (TypeScript-less) API.
export {};

declare global {
  namespace naver.maps {
    class LatLng {
      constructor(lat: number, lng: number);
      lat(): number;
      lng(): number;
    }

    class LatLngBounds {
      extend(latlng: LatLng): LatLngBounds;
    }

    class Point {
      constructor(x: number, y: number);
      x: number;
      y: number;
    }

    class Size {
      constructor(width: number, height: number);
      width: number;
      height: number;
    }

    interface MapOptions {
      center?: LatLng;
      zoom?: number;
    }

    class Map {
      constructor(element: HTMLElement, options?: MapOptions);
      fitBounds(bounds: LatLngBounds): void;
      setCenter(latlng: LatLng): void;
    }

    interface MarkerIcon {
      content: string;
      size?: Size;
      anchor?: Point;
    }

    interface MarkerOptions {
      position: LatLng;
      map?: Map;
      icon?: MarkerIcon;
    }

    class Marker {
      constructor(options: MarkerOptions);
    }

    interface InfoWindowOptions {
      content?: string | HTMLElement;
      borderWidth?: number;
      backgroundColor?: string;
    }

    class InfoWindow {
      constructor(options?: InfoWindowOptions);
      setContent(content: string | HTMLElement): void;
      open(map: Map, anchor: Marker): void;
    }

    namespace Event {
      function addListener(target: Marker | Map, eventName: string, handler: () => void): unknown;
    }

    namespace Service {
      type Status = "OK" | "ERROR";
      const Status: { OK: Status; ERROR: Status };
      const OrderType: { ADDR: string; ROAD_ADDR: string };

      interface GeocodeAddress {
        roadAddress: string;
        jibunAddress: string;
        englishAddress?: string;
        x: string;
        y: string;
      }

      interface GeocodeResponse {
        v2: {
          status: string;
          meta: { totalCount: number };
          addresses: GeocodeAddress[];
        };
      }

      interface ReverseGeocodeRegion {
        area1?: { name: string };
        area2?: { name: string };
        area3?: { name: string };
        area4?: { name: string };
      }

      interface ReverseGeocodeResult {
        name: string; // "roadaddr" | "addr"
        region: ReverseGeocodeRegion;
        land?: {
          type?: string;
          number1?: string;
          number2?: string;
          name?: string;
          addition0?: { type: string; value: string };
        };
      }

      interface ReverseGeocodeResponse {
        v2: {
          status: string;
          results: ReverseGeocodeResult[];
        };
      }

      function geocode(
        options: { query: string },
        callback: (status: Status, response: GeocodeResponse) => void,
      ): void;

      function reverseGeocode(
        options: { coords: LatLng; orders?: string },
        callback: (status: Status, response: ReverseGeocodeResponse) => void,
      ): void;
    }
  }

  interface Window {
    naver?: typeof naver;
    navermap_authFailure?: () => void;
  }
}
