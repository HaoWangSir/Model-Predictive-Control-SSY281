close all;clear;clc;
%% You can use any command in MPT in this assignment

%% Question 1
% write the code to plot X0. In the report, give Pf,  the X0, and your
% motivation for choosing this Pf.


% https://www.mpt3.org/UI/RegulationProblem


A=[1.2 1;0 1]; B=[0;1];

x0=[2;0];

model = LTISystem('A', A, 'B', B);
model.x.min = [-15; -15];
model.x.max = [15; 15];
model.u.min = -1;
model.u.max = 1;


X = Polyhedron('lb',model.x.min,'ub',model.x.max);
U = Polyhedron('lb',model.u.min,'ub',model.u.max);

Q=eye(2); 
R=100;

model.x.penalty = QuadFunction(Q);
model.u.penalty = QuadFunction(R);

C_inf=model.invariantSet();

% Xf=0 as terminal set
Xf   = zeros(2,1);
Tset = Polyhedron( 'Ae', eye(2), 'be', Xf);
model.x.with('terminalSet');
model.x.terminalSet = Tset;

% P chose
% P=[0 0;0 1]; 
PN  = model.LQRPenalty;
Pf = PN.weight;
model.x.with('terminalPenalty');
model.x.terminalPenalty = PN;

N=3;
XN = pre_operation(model,Tset,N);

plot(XN)


%% Question 2
% write the code to plot the requested figures. Provide the figures in your
% report and explain your observation about the error between the state and
% state prediction as N increases.


x0 = [4 -2.6]';
Nsim=100;
N = 1;
mpc = MPCController(model, N);
loop = ClosedLoop(mpc, model);

N= [10, 15, 20];


for i=1:numel(N)
    mpc.N = N(i);
    datasim{i} = loop.simulate(x0,Nsim);
    [~, ~, openloop] = mpc.evaluate(x0);
    mpceval{i} = openloop;
    
    figure('Color','white');
    hold on, grid on;
    plot(0:Nsim, datasim{i}.X', 'Linewidth',3);
    plot(0:N(i), mpceval{i}.X', '-.', 'Linewidth',3, 'Color','black');
    title(sprintf('X - N=%.f',N(i)))
    xlim([0 Nsim])
end

%% Question 3
% no code is needed. Answer in the report

Xf3 = model.reachableSet('X',C_inf,'U',U,'N',1,'direction','forward')
Xf3 = Xf3.intersect(C_inf);

plot(X,'alpha',0.2,'Color','blue', ...
     C_inf,'alpha', 0.2,'Color','red',...
     Xf3,'alpha', 0.5,'Color','red')


%% Question 4
% write a code that calculates the figures and costs. Provide the figures
% and costs in the report. for costs, provide a table in the report that
% provides all costs for all different methods in the question (4 methods,
% each with three different costs as defined in A7 assignment). If you what
% to use some functions in the code, you can write them in different matlab
% files and submit them with the rest of your files

% https://yalmip.github.io/example/standardmpc/
% https://www.mpt3.org/Main/CustomMPC

clearvars
yalmip('clear')

select_case = 2;    % 1, 2 or 3


% Model data
load('HW5_data.mat')
C = 9.2e3;
R = 50;
dt = 3600;
T_lb = 21;
T_ub = 26;
A = 1 - dt/(R*C);
B = dt/C;
rho = 1000;
kappa = 2;

hoursidx = (0:1:23)*12*60 +1;
Pd_h  = Pd.values(hoursidx);
Toa_h = T_oa.values(hoursidx) - 275;
dist = Pd_h*dt/C + Toa_h*dt/(R*C);

% MPC data
N = 24;

T = sdpvar(1,N+1);
u = sdpvar(1,N);
eps_lb = sdpvar(1,N);
eps_ub = sdpvar(1,N);
d = sdpvar(1,N);

con = [];
for i = 1:N
    if (select_case == 1) || (select_case == 2 && i==1) 
        con = [con;   T(i+1) == A*T(i) + B*u(i) + d(i)];
    else
        con = [con;   T(i+1) == A*T(i) + B*u(i)];
    end
    con = [con;   T(i) >= T_lb - eps_lb(i); 
                  T(i) <= T_ub + eps_ub(i)];
    con = [con;   eps_lb(i) >= 0 ; 
                  eps_ub(i) >= 0];
end
objective = norm(u,1) + kappa * norm(u,Inf) + rho * ( norm(eps_lb,1) + norm(eps_ub,1) );

parameters_in = {T(1), d};
solutions_out = {u, T, eps_lb, eps_ub};

controller = optimizer(con, objective,sdpsettings('solver','quadprog'),parameters_in,solutions_out);

T0 = 22;
d0 = dist;
buffer.X(1) = T0;
tf = 24*6;

for i = 1:tf
    inputs = { T0, d0' };
    [solutions,diagnostics] = controller{inputs};    
    U = solutions{1};
    X = solutions{2};
    if diagnostics == 1
        error('The problem is infeasible');
    end
    T0 = A*T0 + B*U(1) + d0(1);

    buffer.X(i+1)    = T0;
    buffer.U(i)      = U(1);
    buffer.d(i)      = d0(1);
    buffer.eps_lb(i) = solutions{3}(1);
    buffer.eps_ub(i) = solutions{4}(1);
    
    d0 = circshift(d0,-1);
end

% Calculate controller performance
ss_idx = 24*5+1:24*6;

Ju = norm(buffer.U(ss_idx),1) * dt;
Jp = norm(buffer.U(ss_idx),Inf);
Je = ( norm(buffer.eps_lb(ss_idx),1) + norm(buffer.eps_ub(ss_idx),1) ) * dt;


figure('Color','white','Position',[156   74  839  670]);
subplot(3,1,1)
plot(ss_idx, buffer.X(ss_idx), 'LineWidth',3)
grid on, xlabel 't [hours]', ylabel 'Temperature [C]'
xlim([min(ss_idx) max(ss_idx)])

subplot(3,1,2)
plot(ss_idx,buffer.U(ss_idx), 'LineWidth',3)
grid on, xlabel 't [hours]', ylabel 'Control input [kW]'
xlim([min(ss_idx) max(ss_idx)])

subplot(3,1,3)
plot(ss_idx,buffer.d(ss_idx), 'LineWidth',3)
grid on, xlabel 't [hours]', ylabel 'Disturbance [kW]'
xlim([min(ss_idx) max(ss_idx)])


sgtitle(sprintf('Controller n: %.f      J_u=%.1f , J_p=%.1f,  J_e=%.1f',select_case,Ju,Jp,Je))



%% Help functions

function Z = pre_operation(model,S,steps)
    X=Polyhedron('lb',model.x.min,'ub',model.x.max);
    U=Polyhedron('lb',model.u.min,'ub',model.u.max);
    Z=S;
    for i=1:steps
       R = model.reachableSet('X', Z, 'U', U, 'N', 1,  'direction', 'backward');
       Z = X.intersect(R);
    end
end