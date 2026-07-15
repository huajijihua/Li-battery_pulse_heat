function metrics = computeWindowMetrics(time_s, sampleValues)
%computeWindowMetrics Compute auditable metrics over an explicit time window.

arguments
    time_s {mustBeNumeric, mustBeReal, mustBeFinite, mustBeVector}
    sampleValues {mustBeNumeric, mustBeReal, mustBeFinite, mustBeVector}
end

time_s = time_s(:);
sampleValues = sampleValues(:);

if numel(time_s) ~= numel(sampleValues)
    error('M3:WindowMetrics:SizeMismatch', ...
        'time_s and sampleValues must contain the same number of samples.');
end

if numel(time_s) < 2
    error('M3:WindowMetrics:InsufficientSamples', ...
        'At least two time samples are required to define a time window.');
end

if any(diff(time_s) <= 0)
    error('M3:WindowMetrics:NonIncreasingTime', ...
        'time_s must be strictly increasing.');
end

windowDuration_s = time_s(end) - time_s(1);
integralValue = trapz(time_s, sampleValues);
squaredIntegral = trapz(time_s, sampleValues .^ 2);

metrics = struct( ...
    'windowStart_s', time_s(1), ...
    'windowEnd_s', time_s(end), ...
    'windowDuration_s', windowDuration_s, ...
    'sampleCount', numel(time_s), ...
    'peak', max(abs(sampleValues)), ...
    'mean', integralValue / windowDuration_s, ...
    'rms', sqrt(squaredIntegral / windowDuration_s), ...
    'integral', integralValue, ...
    'integrationMethod', 'trapezoidal');
end
