classdef computeWindowMetricsTest < matlab.unittest.TestCase
    %computeWindowMetricsTest Verifies SC-02 metric calculations.

    methods (TestClassSetup)
        function addSourceFolder(testCase)
            sourceFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(sourceFolder));
        end
    end

    methods (Test)
        function testZeroSignal(testCase)
            metrics = computeWindowMetrics([0; 0.5; 1], [0; 0; 0]);

            testCase.verifyEqual(metrics.peak, 0, AbsTol=1e-12);
            testCase.verifyEqual(metrics.mean, 0, AbsTol=1e-12);
            testCase.verifyEqual(metrics.rms, 0, AbsTol=1e-12);
            testCase.verifyEqual(metrics.integral, 0, AbsTol=1e-12);
        end

        function testConstantSignal(testCase)
            metrics = computeWindowMetrics([0; 0.2; 0.7; 1], 3 * ones(4, 1));

            testCase.verifyEqual(metrics.peak, 3, AbsTol=1e-12);
            testCase.verifyEqual(metrics.mean, 3, AbsTol=1e-12);
            testCase.verifyEqual(metrics.rms, 3, AbsTol=1e-12);
            testCase.verifyEqual(metrics.integral, 3, AbsTol=1e-12);
        end

        function testSignedSymmetricSignal(testCase)
            metrics = computeWindowMetrics([0; 0.5; 1], [-2; 0; 2]);

            testCase.verifyEqual(metrics.peak, 2, AbsTol=1e-12);
            testCase.verifyEqual(metrics.mean, 0, AbsTol=1e-12);
            testCase.verifyEqual(metrics.rms, sqrt(2), AbsTol=1e-12);
            testCase.verifyEqual(metrics.integral, 0, AbsTol=1e-12);
        end

        function testPulseSignal(testCase)
            metrics = computeWindowMetrics([0; 0.25; 0.5; 0.75; 1], [0; 4; 4; 0; 0]);

            testCase.verifyEqual(metrics.peak, 4, AbsTol=1e-12);
            testCase.verifyEqual(metrics.mean, 2, AbsTol=1e-12);
            testCase.verifyEqual(metrics.rms, sqrt(8), AbsTol=1e-12);
            testCase.verifyEqual(metrics.integral, 2, AbsTol=1e-12);
        end

        function testRejectsNonIncreasingTime(testCase)
            testCase.verifyError( ...
                @() computeWindowMetrics([0; 1; 1], [1; 1; 1]), ...
                'M3:WindowMetrics:NonIncreasingTime');
        end
    end
end
