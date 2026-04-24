export interface SpacingScale {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
}

export interface RadiusScale {
  sm: number;
  md: number;
  lg: number;
}

export const Spacing: SpacingScale = {
  xs: 4,
  sm: 8,
  md: 16,
  lg: 24,
  xl: 40,
};

export const Radius: RadiusScale = {
  sm: 6,
  md: 10,
  lg: 16,
};
