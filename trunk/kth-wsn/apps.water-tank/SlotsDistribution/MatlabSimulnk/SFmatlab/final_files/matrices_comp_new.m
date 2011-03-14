function [A_new,B_new,C_new,D_new]=matrices_comp_new(nA,nB,h)
%**************************************

% Upper Tank:
     Km = 4.6    ;       % m^3/s*V   Detta �r det v�rde som anges i manualen.
     a1 = 10000*pi*(0.0047625/2)^2; % m^2        Detta ar det mista av de tre h?len, "Small".
     A1 = 10000*pi*(0.04445/2)^2; % m^2        Detta �r det v�rde som anges i manualen.
     H1 = 0.25;              % m
init_h1 = 0;                 % m


% Lower Tank:
     a2 = 10000*pi*(0.0047625/2)^2; % m^2
     A2 = 10000*pi*(0.04445/2)^2; % m^2        Detta �r det v�rde som anges i manualen.
     H2 = 0.25;              % m
init_h2 = 0;                 % m
% General
     g=980;
     k1=1;
     k2=1;
    
     % Here we define the point of linearization
     L20=10;
     L10=L20*(a2/a1)^2;
     %Km=5*4.6e-6;
%**************************************
% Definition of the system for control design
% more details in
% http://mechanical.poly.edu/faculty/vkapila/ME325/WaterTank/Water_Tank_Manual.pdf

% The states are x=[L1 z1 L2 z2] and u=Vp 
% L1 - level in tank 1
% L2 - level in tank 2
% z1 - integral state of level 1
% z2 - integral state of level 2

o1=0.635;
o2=0.4763;
alfa1=-1*(a1/A1)*sqrt(g/(2*L10));
beta1=(o2/(o1+o2))*Km/A1; %out 1
beta3=(o1/(o1+o2))*Km/A1; % out 2
alfa2=(-a2/A2)*sqrt(g/(2*L20));
beta2=(a1/A2)*sqrt(g/(2*L10));

% _a is for the first coupled tank system
A_block_a=[alfa1 0; beta2 alfa2];
B_block_a=[beta1]; % to it self
B_block_b=[beta3]; % to the next one

% full A,B,C

%% Without integral control
% select size: 10 processes = 20 states and 10 inputs
nA=20;
nB=10;
A=zeros(nA,nA);
B=zeros(nA,nB);
C=eye(nA);

k=1;
i=1;
while i<nA
    A(i:i+1,k:k+1)=A_block_a;
    k=k+2;
    i=i+2;
end

k=1;
i=3;
while i<nA
    B(i,k)=beta1;
    B(i+1,k+1)=beta3;
    i=i+2;
    k=k+1;
end
B(1,10)=beta1;
B(2,1)=beta3;
B
% k=1;
% i=1;
% j=1;
% while j<=nB
%     B(i,k)=B_block_b;
%     i=i+2;
%     B(i,k)=B_block_a;
%     k=k+1;
%     i=i+2;
%     j=j+1;
% end
% 
% B
% D=zeros(nA,nB);
% 
% 
% %% With integral control
[a,b]=size(B);
k=2; % we need to do integral control of 
% x2,x4,x6 etc etc
nAnew=nA+10; % 10 since we want to track 10 lower tanks out of the 20 tanks
A_new=zeros(nAnew,nAnew);
A_new(1:nA,1:nA)=A;
for i=1:10
    A_new(nA+i,k)=1;
    k=k+2;
end
% 
% 
% 
B_new=zeros(nAnew,b); % first column for original B and second column for the integrator!
B_new(1:nA,1:b)=B;

%B_new(nA:nAnew,b)=-1*ones(nAnew-nA,1);

C_new=[eye(nA) zeros(nA,nAnew-nA)];

D_new=zeros(nA,nB);
% 
% E=[B;zeros(nAnew-nA,nB)];
% sys=ss(A_new,E,C_new,zeros(nA,nB));
% sysd=c2d(sys,h);
% Ed=zeros(nAnew,nB); % disturbance has the same size of the inputs u (nB)
% 
% k=1;
% i=3;
% j=1;
% while j<=nB
%     Ed(i,k)=B_block_a;
%     i=i+2;
%     Ed(i,k)=B_block_a;
%     k=k+1;
%     i=i+2;
%     j=j+1;
% end
% 
% A_new(2,nA-1)=beta2;
% end
Ai=A_new
Bi=B_new
Ci=C_new
Di=D_new