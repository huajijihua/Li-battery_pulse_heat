function motor = build_cam255pt52_motor_data()
%BUILD_CAM255PT52_MOTOR_DATA Return CAM255PT52 motor data for 3806 pulse-heating models.
%
% Data source:
%   1) 255电机LdLq标定表.xlsx
%      - 100C map
%      - q-axis current approximately zero operating line (current angle 90 deg)
%   2) 电驱桥-参数.xlsx
%      - line resistance 15.2-16.8 mOhm at 25C

    motor = struct();
    motor.param_source = 'CAM255PT52 LdLq map + drive axle parameter sheet (2026-05-13)';

    % 100C Ld table extracted from the Iq~=0 line of the detailed map.
    motor.Ld_table_temp_C = 100;
    motor.Ld_table_current_A = [ ...
         20  40  60  80 100 120 140 160 180 200 220 240 260 280 ...
        300 320 340 360 380 400 420 440 460 480 500 520 540 550];
    motor.Ld_table_H = [ ...
        0.000279489586445 0.000278402275353 0.000277151111285 0.000275605548405 ...
        0.000273939731002 0.000272204767629 0.000270498866699 0.000268857771973 ...
        0.000267304619716 0.000265828789866 0.000264400810699 0.000262996767239 ...
        0.000261600320002 0.000260205301406 0.000258802028839 0.000257382623556 ...
        0.000255950195859 0.000254494454826 0.000253009665867 0.000251498553496 ...
        0.000249953137537 0.000248385853253 0.000246794175187 0.000245140263775 ...
        0.000243413684729 0.000241626375555 0.000239794378086 0.000238868115580];

    % Use a mid-high current representative point as the nominal display value.
    motor.Ld_nominal_ref_current_A = 400;
    motor.Ld_nominal_H = interp1( ...
        motor.Ld_table_current_A, motor.Ld_table_H, motor.Ld_nominal_ref_current_A, 'linear');

    % Drive-axle sheet gives line resistance at 25C. Zero-dimensional model uses
    % phase resistance as the branch series resistance for waveform calculation.
    motor.Rs_line_25C_range_ohm = [15.2e-3, 16.8e-3];
    motor.Rs_line_25C_mean_ohm = mean(motor.Rs_line_25C_range_ohm);
    motor.Rs_ref_temp_C = 25;
    motor.Rs_phase_ref_ohm = motor.Rs_line_25C_mean_ohm / 2;
    motor.Rs_phase_range_ohm = motor.Rs_line_25C_range_ohm / 2;
end
