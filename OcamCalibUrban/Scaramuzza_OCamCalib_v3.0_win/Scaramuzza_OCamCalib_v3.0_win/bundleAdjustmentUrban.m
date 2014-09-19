%     Steffen Urban email: steffen.urban@kit.edu
%     Copyright (C) 2014  Steffen Urban
% 
%     This program is free software; you can redistribute it and/or modify
%     it under the terms of the GNU General Public License as published by
%     the Free Software Foundation; either version 2 of the License, or
%     (at your option) any later version.
% 
%     This program is distributed in the hope that it will be useful,
%     but WITHOUT ANY WARRANTY; without even the implied warranty of
%     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%     GNU General Public License for more details.
% 
%     You should have received a copy of the GNU General Public License along
%     with this program; if not, write to the Free Software Foundation, Inc.,
%     51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

function bundleAdjustmentUrban(calib_data, robust)

global weights

if (robust)
    fprintf(1,'Starting robust bundle adjustment\n');
else
    fprintf(1,'Starting bundle adjustment\n');
end

if isempty(calib_data.n_ima) | calib_data.calibrated==0,
    fprintf(1,'\nNo linear estimate available. You must first calibrate your camera.\nClick on "Calibration"\n\n');
    return;
end;

optionsLM=optimset('Display','off',...
                   'TolX',1e-4,...
                   'TolFun',1e-4,...
                   'MaxIter',100,...
                   'Algorithm','levenberg-marquardt');                 
             
if (isempty(calib_data.ocam_model.c) & isempty(calib_data.ocam_model.d) & isempty(calib_data.ocam_model.e))
    calib_data.ocam_model.c=1;
    calib_data.ocam_model.d=0;
    calib_data.ocam_model.e=0;
end

int_par = [calib_data.ocam_model.c,calib_data.ocam_model.d,calib_data.ocam_model.e,calib_data.ocam_model.xc,calib_data.ocam_model.yc];
M = [calib_data.Xt,calib_data.Yt,zeros(size(calib_data.Xt))];

ss0 = calib_data.ocam_model.ss;    
% x0 = [calib_data.ocam_model.xc,calib_data.ocam_model.yc,...
%     calib_data.ocam_model.c,calib_data.ocam_model.d,calib_data.ocam_model.e,...
%     ones(1,size(calib_data.ocam_model.ss,1)-1)];
x0 = [1,1,...
      1,0,0,...
      ones(1,size(calib_data.ocam_model.ss,1))];
lb=[0, 0, -2,-1,-1, zeros(1,size(calib_data.ocam_model.ss,1))];
ub=[2, 2,  2, 1, 1,2*ones(1,size(calib_data.ocam_model.ss,1))];

% lb=[-inf,-inf, -inf,-inf,-inf, -inf*ones(1,size(calib_data.ocam_model.ss,1)-1)];
% ub=[inf,inf,  inf, inf, inf,ones(1,size(calib_data.ocam_model.ss,1)-1)*inf];
offset = 6+calib_data.taylor_order;
for i = calib_data.ima_proc
    R = calib_data.RRfin(:,:,i);
    R(:,3) = cross(R(:,1),R(:,2));
    r = rodrigues(R);
    t = calib_data.RRfin(:,3,i);
    
    x0 = [x0, r(1),r(2),r(3),t(1),t(2),t(3)];
    lb = [lb, -ones(1,6)*inf];
    ub = [ub, ones(1,6)*inf];  
end


weights = ones(2*size(calib_data.Xt,1)*length(calib_data.ima_proc),1);

[x0, ~, vExtr, ~, ~, ~, jacExtr] = lsqnonlin(@bundleErrUrban, x0, ...
                                             -inf*ones(1,length(x0),1), inf*ones(1,length(x0)), ...
                                             optionsLM, calib_data, M, robust);
                                        
calib_data.weights = weights;    
lauf = 0;
for i = calib_data.ima_proc
    RRfinOpt(:,:,i) = rodrigues([x0(offset+1+lauf),x0(offset+2+lauf),x0(offset+3+lauf)]);
    RRfinOpt(:,3,i) = [x0(offset+4+lauf),x0(offset+5+lauf),x0(offset+6+lauf)]';
    lauf = lauf+6;
end

% ssc = [x0(6) 0 x0(7:offset)];
ssc = [x0(6:offset)];
calib_data.ocam_model.ss=ss0.*ssc';
calib_data.ocam_model.xc=calib_data.ocam_model.xc * x0(1);
calib_data.ocam_model.yc=calib_data.ocam_model.yc * x0(2);
calib_data.ocam_model.c = x0(3);
calib_data.ocam_model.d = x0(4);
calib_data.ocam_model.e = x0(5);

%% calc standard deviation of EO
sigma0q = 1^2;
v = vExtr;
% J = jacExtr(:,offset+1:end);
J = jacExtr;
[rows,cols]=size(J);   
Qll = sigma0q*eye(size(J,1),size(J,1));
P0 = inv(Qll);
% calib_data.statEO.ms = v'*v;
% calib_data.statEO.rmse = sqrt(v'*v);
% a posteriori variance
calib_data.statEO.sg0 = sqrt((v'*P0*v) / (rows-cols));
% empirical covariance matrix
Exx = pinv(J'*P0*J);
calib_data.statEO.Exx = Exx(offset+1:end,offset+1:end);
calib_data.statEO.varEO = diag(calib_data.statEO.Exx);        % variance of ext ori parameters
calib_data.statEO.stdEO = calib_data.statEO.sg0 * sqrt(diag(calib_data.statEO.Exx));      % standard deviation of ext ori parameters

calib_data.statIO.Exx = Exx(1:offset,1:offset);
calib_data.statIO.varIO = diag(calib_data.statIO.Exx);        % variance of ext ori parameters
calib_data.statIO.stdIO = calib_data.statEO.sg0 * sqrt(diag(calib_data.statIO.Exx));      % standard deviation of ext ori parameters

%% calc standard deviation of IO
% calib_data.statIO.Exx = Exx;
% calib_data.statIO.varIO = diag(calib_data.statIO.Exx);        % variance of ext ori parameters
% calib_data.statIO.stdIO = sqrt(calib_data.statIO.varIO);      % standard deviation of ext ori parameters

calib_data.optimized = true;
calib_data.RRfin = RRfinOpt;

M = [calib_data.Xt,calib_data.Yt,ones(size(calib_data.Xt,1),1)];
% use own reprojection function that respects the weights if robust==true
% [err,stderr,MSE] = reprojectpoints_advUrban(calib_data.ocam_model, calib_data.RRfin, calib_data.ima_proc, calib_data.Xp_abs, calib_data.Yp_abs, M,calib_data.weights);

rms = sqrt(sum(v.^2)/length(v));

ss = calib_data.ocam_model.ss;
ss

calib_data.rms = rms;

[calib_data.ocam_model.pol, ...
    calib_data.ocam_model.err, ...
    calib_data.ocam_model.N] = findinvpoly(calib_data.ocam_model.ss, calib_data.I{1});

t1=calib_data.ocam_model.xc;
t2=calib_data.ocam_model.yc;
calib_data.ocam_model.xc=t2;
calib_data.ocam_model.yc=t1;
